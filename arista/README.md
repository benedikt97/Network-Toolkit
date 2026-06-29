1. Setup Key in Launchpad.
API-Key must have access rights to WM, the locations and what else should be accessed
2. Get API Base Url from CV-CUE / System / Advanced Setting / Base URLs for APIs
2. Export Key and URL to Environment
```
export LAUNCHPAD_KEY_ID="<yourid>"
export LAUNCHPAD_KEY_VALUE="<yourkey>"
export WM_BASE_URL="<yourbaseurl>"

```
3. Execute Script
change-psk.py [-h] --ssid SSID --location LOCATION --newpsk NEWPSK

Hint:
If you want to target your root node configuration you need to specify the name of the root node for --location.