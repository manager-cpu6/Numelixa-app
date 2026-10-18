# Android setup notes

Generate the Android project with Flutter stable if it is not yet present:
```sh
flutter create --platforms=android --org com.numelixa .
```
Then verify that `android/app/build.gradle` applies the Google Services Gradle plugin and uses the package/application ID registered in Firebase. Keep `google-services.json` out of Git and supply it through `FIREBASE_GOOGLE_SERVICES_JSON_BASE64`.

For production signing, create a private release keystore locally and add its base64 plus passwords/alias as GitHub Actions secrets. Never commit the keystore or passwords.
