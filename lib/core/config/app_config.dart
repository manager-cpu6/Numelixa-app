class AppConfig {
  AppConfig._();
  static const apiBase = String.fromEnvironment(
    'NUMELIXA_API_BASE',
    defaultValue: 'https://numelixa.com',
  );
  static const pushRegistrationPath = String.fromEnvironment(
    'NUMELIXA_PUSH_REGISTER_PATH',
    defaultValue: '/api/notifications/register',
  );
}
