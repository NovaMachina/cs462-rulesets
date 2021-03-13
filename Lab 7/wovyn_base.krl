ruleset wovyn_base {
    meta {
        use module io.picolabs.wrangler alias wrangler
        use module io.picolabs.subscription alias subs
        use module twillo_app alias twillo
        use module sensor_profile alias profile

        shares getManager
    }

    global {
        getManager = function() {
            subs:established().filter(function(x) {x{"Tx_role"} == "management"}).head(){"Tx"}
        }
    }

    rule process_heartbeat {
        select when wovyn heartbeat
        pre {
            genericThing = event:attrs{"genericThing"};
        }

        if(genericThing != "") then send_directive("Temperature Recieved");
        
        fired {
            log info <<TEMPERATURE IN PROCESS_HEARTBEAT: #{genericThing{"data"}{"temperature"}[0]{"temperatureC"}}>>
            raise wovyn event "new_temperature_reading" attributes {
                "temperature": genericThing{"data"}{"temperature"}[0],
                "timestamp": time:now()
            } if (genericThing != "")
        }
    }

    rule find_high_temps {
        select when wovyn new_temperature_reading

        pre {
            temperature = event:attrs{"temperature"}.klog("TEMPERATURE IN FIND_HIGH_TEMPS PRE: ")
            temperatureC = temperature{"temperatureC"}
        }

        if(temperature{"temperatureC"} > ent:temperature_threshold) then send_directive("Temperature over threshold");

        fired {
            log info <<TemperatureC: #{temperatureC}>>
            raise wovyn event "threshold_violation" attributes {
                "temperature": temperature,
                "threshold": profile:profile(){"threshold"},
                "timestamp": event:attrs{"timestamp"}
            } if (temperature{"temperatureC"} > profile:profile(){"threshold"})
        }
    }

    rule threshold_notification {
        select when wovyn threshold_violation
        pre {
            temperature = event:attrs{"temperature"}.klog("TEMPERATURE IN THRESHOLD_NOTIFICATION: ")
            threshold = event:attrs{"threshold"}
            timestamp = event:attrs{"timestamp"}
            name = profile:profile(){"name"}
            message = <<Temperature #{temperature{"temperatureC"}} is higher than allotted temperature of #{threshold}C at #{timestamp} on #{name}>>
        }
        event:send({
            "eci": getManager(),
            "domain": "sensor",
            "type": "threshold_violation",
            "attrs": {
                "message": message
            }
        })
    }

    rule capture_initial_state {
        select when wrangler ruleset_installed
            where event:attrs{"rids"} >< meta:rid
        event:send({
            "eci": wrangler:parent_eci(),
            "domain": "sensor",
            "type": "identify",
            "attrs": {
                "sensor_id": profile:profile(){"sensor_id"},
                "wellKnown_eci": subs:wellKnown_Rx(){"id"},
            }
        })
    }

    rule auto_accept {
        select when wrangler inbound_pending_subscription_added
        pre {
            my_role = event:attrs{"Rx_role"}
            their_role = event:attrs{"Tx_role"}
        }
        if my_role == "sensor" && their_role == "management" then noop()
        fired {
            raise wrangler event "pending_subscription_approval"
                attributes event:attrs
            ent:subscriptionTx := event:attrs{"Tx"}
        } else {
            raise wrangler event "inbound_rejection"
                attributes event:attrs
        }
    }
}