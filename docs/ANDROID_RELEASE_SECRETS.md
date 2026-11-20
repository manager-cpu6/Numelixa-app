# Android release prerequisites

The feature branch can run Flutter analysis and tests without production credentials. A verified release APK requires the existing Firebase Android configuration and the original application signing key.

## GitHub Actions secrets

Open **GitHub → manager-cpu6/Numelixa-app → Settings → Secrets and variables → Actions** and configure:

| Secret | Required value |
|---|---|
| FIREBASE_GOOGLE_SERVICES_JSON_BASE64 | Base64 of the Firebase `google-services.json` for package `com.numelixa.app` |
| ANDROID_KEYSTORE_BASE64 | Base64 of the original release `.jks` file; alternatively use the two split secrets below |
| ANDROID_KEYSTORE_BASE64_PART1 | First part of the same original keystore Base64 |
| ANDROID_KEYSTORE_BASE64_PART2 | Second part of the same original keystore Base64 |
| ANDROID_KEYSTORE_PASSWORD | Original keystore password |
| ANDROID_KEY_ALIAS | Original release key alias |
| ANDROID_KEY_PASSWORD | Original key password |

Use either ANDROID_KEYSTORE_BASE64 or both split secrets. Do not create a new signing key for an existing installation: a different signing certificate prevents Android from installing the update over the current app.

## Firebase configuration requirements

Download the current `google-services.json` from Firebase for the existing Android app:
- Firebase project: `numelixa`
- Package: `com.numelixa.app`
- Android app ID: `1:832390289699:android:963bd5705215947fb51496`

The workflow verifies that the JSON contains this package and both Android OAuth client type 1 and Web OAuth client type 3. Register the original release certificate SHA-1 in Firebase/Google Cloud OAuth before downloading the updated JSON.

## Base64 from Termux

For a file on the device, create a single-line Base64 value without printing the underlying secret into ChatGPT:

```bash
base64 -w0 google-services.json > google-services.base64.txt
base64 -w0 original-release.jks > release-keystore.base64.txt
```

If the Base64 output is too large for one GitHub secret, split it into two consecutive parts and store them as `ANDROID_KEYSTORE_BASE64_PART1` and `ANDROID_KEYSTORE_BASE64_PART2`. Preserve the exact order and do not add spaces or line breaks.

Never commit `google-services.json`, `.jks`, passwords, OAuth client secrets or Base64 secret material to the repository. Never paste the secret values into a chat.

After adding the secrets, rerun the draft PR workflow. The release job verifies the keystore certificate, package name, APK signature and in-place update compatibility before uploading artifacts.
