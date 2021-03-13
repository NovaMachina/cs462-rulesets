ruleset temperature_store {
    meta {
        provides temperatures, threshold_violations, inrange_temperatures
        shares temperatures, threshold_violations, inrange_temperatures
    }

    global {
        temperatures = function() {
            ent:temperature_record
        }
        threshold_violations = function() {
            ent:violation_record
        }
        inrange_temperatures = function() {
            inrange = ent:temperature_record.filter(function(v,k){
                ent:violation_record.none(function(x) {
                    v == x
                })
            })
            inrange
        }
    }

    rule initialize {
        select when wrangler ruleset_installed
            where event:attrs{"rids"} >< meta:rid
        pre {

        }
        always {
            ent:temperature_record := []
            ent:violation_record := []
        }
    }

    rule collect_temperatures {
        select when wovyn new_temperature_reading
        pre {
            temperature = event:attrs.get(["temperature", "temperatureC"])
            timestamp = event:attrs.get("timestamp")
        }
        send_directive("Recording Temperature")
        fired {
            ent:temperature_record := ent:temperature_record.defaultsTo([]).append({"temperatureC": temperature, "timestamp": timestamp})
        }
    }

    rule collect_threshold_violations {
        select when wovyn threshold_violation
        pre {
            temperature = event:attrs.get(["temperature", "temperatureC"])
            timestamp = event:attrs.get("timestamp")
        }
        send_directive("Recording Temperature Violation")
        fired {
            ent:violation_record := ent:violation_record.defaultsTo([]).append({"temperatureC": temperature, "timestamp": timestamp})
        }
    }

    rule clear_temperatures {
        select when sensor reading_reset

        send_directive("Clearing Temperature and Violation store")

        always {
            ent:temperature_record := []
            ent:violation_record := []
        }
    }
}