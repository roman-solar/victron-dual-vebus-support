#!/usr/bin/env python
# -*- coding: utf-8 -*-

import json
import logging
import time

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

"""
On startup, pass DbusDeltas a list of classes that you want to monitor, and the paths of those classes.
An example of a device class is com.victronenergy.battery. Then, call DbusDeltas.get_deltas() periodically.
For each dbus-service in a class that it finds, for example .battery.ttyO1 and battery.ttO2, it will
calculate the difference between the old and the new value of all the required paths. Then it adds all of
them up and give you the result. At the same time it will refresh the baseline, when required.

Notes and exceptions:
    - The code expect counts to always count upwards. Because of it, the delta can never be < 0. In case
      (New - Old) is < 0, probably that counter has been reset or overflowed and restarted at 0. Right now
      this code just returns 0 in that case.
      TODO: could be improved and just return the new value. But then we do need to make sure that it was
      really an overflow. Not some user reset of counters.
"""
def rename_dict_key(dict, old_key, new_key):
    dict[new_key] = dict.pop(old_key)

class DbusDeltas(object):
    # __init__ parameters:
    #   - dbusmonitor: an initialized instance of DbusMonitor
    #   - services_and_paths: dictionary, with an identifier as the key, and again a dictionary as the value.
    #     that second dictionary needs to have these two keys:
    #        1) services: a list of tuples containing servicename and instance
    #        2) paths: a list of the paths that need to be tracked
    #     For example{'vebus': {'services': set(('com.victronenergy.vebus.ttyO1', 0)), 'paths': ['/kWhcounter1]}
    def __init__(self, dbusmonitor, services_and_paths):
        self._dbusmonitor = dbusmonitor
        self._baseline = {}
        self._services_and_paths = services_and_paths
        self.baselinetimestamp = None

        self._config = self._load_config()
        self._vebus_input_overrides = self._load_vebus_input_overrides(
            self._config.get('vebus_input_overrides', {}))
        self.cross_vebus_passthrough_enabled = (
            self._config.get('cross_vebus_passthrough', {}).get('enabled') is True)

        # Store the initial baseline
        self.get_deltas(refreshbaseline=True)

    @staticmethod
    def _load_config():
        path = '/data/setupOptions/MultiVebusSupport/config.json'
        try:
            with open(path, 'r') as f:
                config = json.load(f)
        except FileNotFoundError:
            logger.info("Multi-VE.Bus config file not found: %s", path)
            return {}
        except (OSError, ValueError, TypeError) as e:
            logger.warning("Unable to load multi-VE.Bus config from %s: %s", path, e)
            return {}

        if not isinstance(config, dict):
            logger.warning("Ignoring multi-VE.Bus config: top-level JSON value is not an object")
            return {}
        return config

    @staticmethod
    def _load_vebus_input_overrides(data):
        if not isinstance(data, dict):
            logger.warning("Ignoring VE.Bus AC input overrides: value is not an object")
            return {}

        overrides = {}
        for instance, inputs in data.items():
            if not isinstance(inputs, dict):
                logger.warning("Ignoring VE.Bus override for DeviceInstance %s: value is not an object", instance)
                continue

            parsed_inputs = {}
            for input_number, role in inputs.items():
                try:
                    input_number = int(input_number)
                    role = int(role)
                except (TypeError, ValueError):
                    logger.warning("Ignoring invalid VE.Bus override %s/%s=%r", instance, input_number, role)
                    continue

                if input_number not in (1, 2) or role not in (1, 2):
                    logger.warning("Ignoring unsupported VE.Bus override %s/%s=%r", instance, input_number, role)
                    continue

                parsed_inputs[input_number] = role

            if parsed_inputs:
                try:
                    instance = int(instance)
                except (TypeError, ValueError):
                    logger.warning("Ignoring VE.Bus override with invalid DeviceInstance: %r", instance)
                    continue
                overrides[instance] = parsed_inputs

        if overrides:
            logger.info("Loaded VE.Bus AC input overrides: %s", overrides)
        return overrides

    def get_vebus_input_type(self, instance, input_number):
        override = self._vebus_input_overrides.get(instance, {}).get(input_number)
        if override is not None:
            return override

        path = '/Settings/SystemSetup/AcInput%s' % input_number
        return 2 if self._dbusmonitor.get_value(
            'com.victronenergy.settings', path) == 2 else 1

    def add_service(self, servicename, instance, identifier):
        self._services_and_paths[identifier]['services'].add((servicename, instance))
        self._baseline[servicename] = {}
        for path in self._services_and_paths[identifier]['paths']:
            value = self._dbusmonitor.get_value(servicename, path)
            if value is not None:
                self._baseline[servicename][path] = self._dbusmonitor.get_value(servicename, path)

    def get_all_services(self, identifier):
        try:
            return list(self._services_and_paths[identifier]['services'])
        except KeyError:
            return ()

    def remove_all_services(self, identifier):
        for (servicename, instance) in list(self._services_and_paths[identifier]['services']):
            self.remove_service(servicename, identifier)

    def remove_service(self, servicename, identifier=None):
        # TODO: it is necessary to do something in case we still want to maintain the deltas calculated
        # until now for the service being removed. Since how it is now, when a MPPT goes offline at 17:55,
        # because the sun goes down and it switches off, it leaves the dbus, triggering a call to this
        # function, which will remove it.

        if servicename in self._baseline:
            del self._baseline[servicename]

        for id, details in self._services_and_paths.items():
            if identifier and identifier != id:
                continue

            for s, i in list(details['services']):
                if servicename == s:
                    details['services'].discard((s, i))

    def has_service(self, servicename):
        return servicename in self._baseline

    # Gets the new value from the dbus, adds the delta to the result dict, and stores the new value. Set
    # refreshbaseline to True when you want to store the current countervalues as the new baseline.
    # Returns a tuple (baselinetimestamp, deltas, rawdeltas, servicecountsdict)
    def get_deltas(self, refreshbaseline):
        newbaseline = {}
        deltas = {}
        rawdeltas = {}
        servicecounts = {}

        for identifier, details in self._services_and_paths.items():
            deltas[identifier] = {}
            servicecounts[identifier] = {}
            for path in details['paths']:
                delta = 0
                servicecount = 0
                for service, instance in details['services']:
                    newvalue = self._dbusmonitor.get_value(service, path)

                    # Invalid / non existing value? Skip to next service
                    if newvalue is None:
                        continue

                    # Service and path are also in the baseline? We have a value! Store it.
                    if service in self._baseline and path in self._baseline[service]:
                        v = max(newvalue - self._baseline[service][path], 0)
                        delta += v
                        servicecount += 1

                        if service not in rawdeltas:
                            rawdeltas[service] = {}

                        rawdeltas[service][path] = (instance, v)

                    if refreshbaseline:
                        if service not in newbaseline:
                            newbaseline[service] = {}

                        # there is a new value, so store it in the new baseline:
                        newbaseline[service][path] = newvalue

                # Store the delta in the result
                deltas[identifier][path] = delta
                servicecounts[identifier][path] = servicecount

        oldbaselinetimestamp = self.baselinetimestamp

        if refreshbaseline:
            # throw away the old baseline, and replace with the new one.
            self._baseline = newbaseline
            self.baselinetimestamp = time.time()

        self._convertvebus_acin1and2_to_gensetandmains(deltas, rawdeltas)

        return [oldbaselinetimestamp, deltas, rawdeltas, servicecounts]

    def _convertvebus_acin1and2_to_gensetandmains(self, deltas, rawdeltas):
        # ======= Change acin 1 and acin 2 into genset and mains =======

        if 'vebus' not in deltas:
            return

        vebus = deltas['vebus']
        converted = {
            '/Energy/GridToAcOut': 0,
            '/Energy/GensetToAcOut': 0,
            '/Energy/GridToDc': 0,
            '/Energy/GensetToDc': 0,
            '/Energy/AcOutToGrid': 0,
            '/Energy/AcOutToGenset': 0,
            '/Energy/DcToGrid': 0,
            '/Energy/DcToGenset': 0,
        }

        # Classify each VE.Bus service before aggregation. Unless a per-device
        # override is configured, the standard global AC input roles are used.
        for service, values in rawdeltas.items():
            if not service.startswith('com.victronenergy.vebus.'):
                continue

            instance = next((item[0] for item in values.values()), None)
            if instance is None:
                continue

            def raw(path):
                item = values.get(path)
                return item[1] if item is not None else 0

            for input_number in (1, 2):
                role = self.get_vebus_input_type(instance, input_number)
                suffix = str(input_number)

                if role == 1:
                    converted['/Energy/GridToAcOut'] += raw('/Energy/AcIn%sToAcOut' % suffix)
                    converted['/Energy/GridToDc'] += raw('/Energy/AcIn%sToInverter' % suffix)
                    converted['/Energy/AcOutToGrid'] += raw('/Energy/AcOutToAcIn%s' % suffix)
                    converted['/Energy/DcToGrid'] += raw('/Energy/InverterToAcIn%s' % suffix)
                else:
                    converted['/Energy/GensetToAcOut'] += raw('/Energy/AcIn%sToAcOut' % suffix)
                    converted['/Energy/GensetToDc'] += raw('/Energy/AcIn%sToInverter' % suffix)
                    converted['/Energy/AcOutToGenset'] += raw('/Energy/AcOutToAcIn%s' % suffix)
                    converted['/Energy/DcToGenset'] += raw('/Energy/InverterToAcIn%s' % suffix)

        vebus.update(converted)

        # Rename Inverter to Dc, so we are consistent with above
        rename_dict_key(vebus, '/Energy/InverterToAcOut', '/Energy/DcToAcOut')
        rename_dict_key(vebus, '/Energy/OutToInverter', '/Energy/AcOutToDc')
