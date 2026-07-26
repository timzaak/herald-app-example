# app

## Herald authentication configuration

The app defaults to the Fornetcode production realm:

- `HERALD_BASE_URL=https://auth.fornetcode.com`
- `HERALD_REALM_ID=admin`
- `HERALD_CLIENT_ID=fornetcode-app`
- `HERALD_CLIENT_APP_UUID=` (required for Stripe/Creem purchase options)

Override any of these values when running against another environment:

```shell
flutter run --dart-define=HERALD_BASE_URL=http://localhost:8080 --dart-define=HERALD_REALM_ID=admin --dart-define=HERALD_CLIENT_ID=fornetcode-app --dart-define=HERALD_CLIENT_APP_UUID=<client-app-uuid>
```

```shell
## freezed
dart run build_runner watch -d
```


Developed with Google Jules. 
