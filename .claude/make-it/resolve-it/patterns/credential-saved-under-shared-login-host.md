---
name: credential-saved-under-shared-login-host
signals: [login saved but "no credentials" for the site, saved credential never read, credential host differs from the job's host, host looks like id./login./auth./sso. on the vendor's domain]
seen: 2026-11-06 (1 incident)
---
## Shape
A person saves a login under the address their browser showed while signing in -- the vendor's
shared sign-in page -- instead of the site that holds the data. Lookups by the data site's host never
find it; the job waits for credentials that "were provided".
## How to confirm
Compare the stored credential's host with the job's host and with the lookup rule (exact host, then
parent domain). Check the credential's access log: never read.
## Fix
Refuse the shared sign-in host at save time with plain words ("type the site you get the files
from"), in the one check every save path uses.
## Prevent
Help text that names the right address; a test per refused host.
