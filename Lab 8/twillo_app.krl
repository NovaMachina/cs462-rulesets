ruleset twillo_app {
    meta {
        use module twillo_sdk alias sdk
            with
                accountSID = meta:rulesetConfig{"account_sid"}
                authToken = meta:rulesetConfig{"auth_token"}
        shares lastResponse, messages
    }

    global {
        lastResponse = function() {
            {}.put(ent:lastTimestamp, ent:lastResponse)
        }

        messages = function(pageSize = "", sending = "", recieving = "") {
            sdk:messages(pageSize, sending, recieving)
        }
    }

    rule send_message {
        select when message send
            to re#(\d{10})#
            content re#(.+)#
            setting(to, content)
        sdk:sendMessage(to, content) setting(response)
        fired {
            ent:lastResponse := response
            ent:lastTimestamp := time:now()
            raise message event "sent" attributes event:attrs
        }
    }
}