# Frame.io integration setup

OpenPocketCine can upload clips to Frame.io through the **Frame.io Platform API (v4)** with
**OAuth 2.0 (PKCE)** via **Adobe IMS**. There is no client secret. The feature is **disabled**
in builds that are not configured. Call this **Frame.io upload** in public copy.

> **Requires iOS 17.4+** for `ASWebAuthenticationSession`.

## 1. Register an OAuth app in Adobe Developer Console (one time)

1. Sign in to the [Adobe Developer Console](https://developer.adobe.com/console).
2. **Create new project** (e.g. `OpenPocketCine`).
3. **Add API** → search for **Frame.io API** → add it to the project.
4. Under **Credentials**, choose **OAuth Native App** (PKCE — no client secret).
5. Open the credential → copy **Client ID** and the full **Default redirect URI**.

Adobe **auto-generates** the Native App redirect URI. It looks like:

```text
adobe+{unique-id}://adobeid/{your-client-id}
```

Copy it character-for-character from the console. Your Frame.io account must be a **V4 account
linked to the same Adobe ID**.

## 2. Configure the app — without committing credentials

```sh
cp ios/OpenPocketCine/Frameio.local.xcconfig.example ios/OpenPocketCine/Frameio.local.xcconfig
```

Edit the gitignored local file:

```xcconfig
FRAMEIO_CLIENT_ID = your_adobe_native_app_client_id
FRAMEIO_REDIRECT_URI = adobe+yourid://adobeid/your_client_id
FRAMEIO_URL_SCHEME = adobe+yourid
```

| Field | Source |
| --- | --- |
| `FRAMEIO_CLIENT_ID` | **Client ID** on the credential page |
| `FRAMEIO_REDIRECT_URI` | Full **Default redirect URI** |
| `FRAMEIO_URL_SCHEME` | Everything **before** `://` in the redirect URI |

The committed `Frameio.xcconfig` defaults these to empty — fresh clones build without Frame.io
until you add the local file. Delete and reinstall the app after changing redirect/scheme so
stale Keychain tokens are cleared.
