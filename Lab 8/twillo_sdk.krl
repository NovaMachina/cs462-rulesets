ruleset twillo_sdk {
    meta {
        configure using
            accountSID = ""
            authToken = ""

        provides sendMessage, messages
    }
    global {
        base_url = "https://api.twilio.com/2010-04-01/Accounts"

        sendMessage = defaction(to, message) {
            body = {"To": to.klog("TO: "), "From": +16107568834, "Body": message}
            cred = {"username": accountSID, "password": authToken}
            http:post(<<#{base_url}/#{accountSID}/Messages.json>>, form=body, auth=cred) setting(response)
            return response
        }

        messages = function(pageSize = "", sending = "", recieving = "") {
            initialMap = {
                "PageSize": pageSize,
                "To": recieving,
                "From": sending
            }

            queryString = initialMap.filter(function(v, k) {v != ""})

            cred = {"username": accountSID, "password": authToken}
            response = http:get(<<#{base_url}/#{accountSID}/Messages.json>>, qs=queryString, auth=cred)
            response{"content"}.decode()
        }
    }
}