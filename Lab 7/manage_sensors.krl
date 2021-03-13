ruleset manage_sensors {
    meta {
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subs
        use module sensor_profile alias profile
        use module twillo_app alias twillo

        shares nameFromID, showChildren, sensors, all_temperatures, subscriptions, sensor_list
    }

    global {
        default_threshold = 40
        default_number = 5129491100

        nameFromID = function(sensor_id) {
            "Sensor: " + sensor_id + " Pico"
        }

        showChildren = function() {
            wrangler:children()
        }

        sensors = function() {
            subscriptions().filter(function(x) {x{"Tx_role"} == "sensor"})
        }

        sensor_list = function() {
            ent:sensors
        }

        all_temperatures = function() {
            sensors().map(function(v){
                value = v{"Tx"}.klog("VALUE: ");
                answer = wrangler:picoQuery(value, "temperature_store", "temperatures", _host = v{"Tx_host"})
                answer
            }).values().reduce(function(a, b) {
                a.append(b)
            })
        }

        subscriptions = function() {
            subs:established()
        }
    }

    rule initialize_sensors {
        select when sensor needs_initialization
        always {
            ent:sensors := {}
        }

    }

    rule sensor_already_exists {
        select when sensor new_sensor
        sensor_id re#(.+)#
        setting(sensor_id)
        pre {
            exists = ent:sensors && ent:sensors >< sensor_id
        }
        if exists then
          send_directive("sensor_ready", {"sensor_id":sensor_id})
    }

    rule sensor_does_not_exist {
        select when sensor new_sensor
        sensor_id re#(.+)#
        setting(sensor_id)
        pre {
            exists = ent:sensors && ent:sensors >< sensor_id
        }
        if not exists then noop();

        fired {
            raise wrangler event "new_child_request"
                attributes {
                    "name": nameFromID(sensor_id),
                    "backgroundColor": "#ff69b4",
                    "sensor_id": sensor_id
                }
        }
    }

    rule store_new_sensor {
        select when wrangler new_child_created
        foreach {
            "temperature_store" : {},
            "sensor_profile": {},
            "twillo_sdk": {},
            "twillo_app": {"account_sid":"AC1b3fee8ad081c63503818c1c9ee09d4e","auth_token":"0e805aa024a348177090544d1650b56c"},
            "wovyn_base": {},
            "io.picolabs.wovyn.emitter": {}
        } setting(config, rule_id)
        pre {
            the_sensor = {"eci": event:attrs{"eci"}}
            sensor_id = event:attrs{"sensor_id"}
            name = event:attrs{"name"}.klog("passed in name: ")
        }
        if sensor_id.klog("found sensor_id") then
            event:send(
                {
                    "eci": the_sensor.get("eci"),
                    "eid": "install_ruleset",
                    "domain": "wrangler", "type": "install_ruleset_request",
                    "attrs": {
                        "absoluteURL": meta:rulesetURI,
                        "rid": rule_id,
                        "config": config,
                        "sensor_id": sensor_id
                    }
                }
            )
        fired {
            ent:sensors{sensor_id} := the_sensor on final
            raise sensor event "rulesets_installed"
                attributes {
                    "eci": the_sensor.get("eci"),
                    "name": name,
                    "sensor_id": sensor_id
                } on final
        }
    }

    rule rulesets_installed {
        select when sensor rulesets_installed
        pre {
            eci = event:attrs{"eci"}
            name = event:attrs{"name"}
        }
        if eci.klog("found sensor eci") then
            event:send(
                {
                    "eci": eci,
                    "eid": "install_profile",
                    "domain": "sensor", "type": "profile_updated",
                    "attrs": {
                        "new_name": name,
                        "new_number": default_number,
                        "new_threshold": default_threshold
                    }
                }
            )
    }

    rule notify_creation {
        select when sensor rulesets_installed
        pre {
            sensor_id = event:attrs{"sensor_id"}
        }
        send_directive("sensor_created", {"sensor_id": sensor_id})
    }

    rule remove_sensor {
        select when sensor unneeded_sensor
        pre {
            sensor_id = event:attrs{"sensor_id"}
            exists = ent:sensors >< sensor_id
            eci_to_delete = ent:sensors{[sensor_id, "eci"]}
        }
        if exists && eci_to_delete then
            send_directive("deleting sensor", {"sensor_id": sensor_id})
        fired {
            raise wrangler event "child_deletion_request"
                attributes {
                    "eci": eci_to_delete
                }
            clear ent:sensors{sensor_id}
        }
    }

    rule query_child {
        select when sensor query_sensor
        pre {
            eci = event:attrs{"sensor_eci"}
            ruleset_id = event:attrs{"ruleset_id"}
            function_name = event:attrs{"funciton_id"}
            args = event:attrs{"args"}
            answer = wrangler:picoQuery(eci, ruleset_id, function_name, {}.put(args))
        }
        if answer{"error"}.isnull() then send_directive(answer);
    }

    rule accept_wellKnown {
        select when sensor identify
        pre {
            sensor_id = event:attrs{"sensor_id"}
            wellKnown_eci = event:attrs{"wellKnown_eci"}
        }
        fired {
            ent:sensors{[sensor_id, "wellKnown_eci"]} := wellKnown_eci
            raise sensor event "new_subscription_request"
                attributes {
                    "wellKnown_eci": wellKnown_eci,
                    "sensor_id": sensor_id
                }
        }
    }

    rule make_a_subscription {
        select when sensor new_subscription_request
        event:send({
            "eci": event:attrs{"wellKnown_eci"},
            "domain": "wrangler",
            "name": "subscription",
            "attrs": {
                "wellKnown_Tx": subs:wellKnown_Rx(){"id"},
                "Rx_role": "sensor",
                "Tx_role": "management",
                "name": "sensor:"+event:attrs{"sensor_id"}+"-management",
                "channel_type": "subscription"
            }
        })
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        pre {
            my_role = event:attrs{"Rx_role"}
            their_role = event:attrs{"Tx_role"}
        }
        if my_role == "management" && their_role == "sensor" then noop()
        fired {
            raise wrangler event "pending_subscription_approval"
                attributes event:attrs
            ent:subscriptionTx := event:attrs{"Tx"}
        } else {
            raise wrangler event "inbound_rejection"
                attributes event:attrs
        }
    }

    rule introduce_sensor_to_manager {
        select when sensor add_sensor
        pre {
            wellKnown_eci = event:attrs{"wellKnown_eci"}
            Tx_host = event:attrs{"their_host"}
        }
        event:send({
            "eci": meta:eci,
            "domain": "wrangler",
            "name": "subscription",
            "attrs": {
                "wellKnown_Tx": wellKnown_eci,
                "Rx_role": "management",
                "Tx_role": "sensor",
                "Tx_host": Tx_host,
                "name": event:attrs{"name"}+"-management",
                "channel_type": "subscription"
            }
        })
    }

    rule threshold_violation {
        select when sensor threshold_violation
        pre {
            message = event:attrs{"message"}
        }
        send_directive("send-message")

        fired {
            raise message event "send" attributes {
                "to": profile:profile(){"notify_number"},
                "content": message
            }
        }
    }
}