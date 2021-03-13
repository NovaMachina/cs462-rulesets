ruleset sensor_profile {
    meta { 
        shares profile
        provides profile
    }
    global {
        profile = function() {
            {
                "threshold": ent:temperature_threshold,
                "notify_number": ent:notify_number,
                "location": ent:locaiton,
                "name": ent:name,
                "sensor_id": ent:sensor_id
            }
        }
    }
    rule update_profile {
        select when sensor profile_updated
        pre {
            new_threshold = event:attrs{"new_threshold"} || (ent:temperature_threshold)
            new_number = event:attrs{"new_number"} || (ent:notify_number)
            new_location = event:attrs{"new_location"} || (ent:locaiton)
            new_name = event:attrs{"new_name"} || (ent:name)
        }
        send_directive("Updating profile")
        always {
            ent:temperature_threshold := new_threshold
            ent:notify_number := new_number
            ent:locaiton := new_location
            ent:name := new_name
        }
    }

    rule initialize {
        select when wrangler ruleset_installed
            where event:attrs{"rids"} >< meta:rid
        pre {
            sensor_id = event:attrs{"sensor_id"}.klog("SENSOR ID: ")
        }
        always {
            ent:sensor_id := sensor_id
            ent:temperature_threshold := 40
            ent:notify_number := 5129491100
            ent:locaiton := "Default Location"
            ent:name := "Sensor Name"
        }
    }
}