import 'background_job.dart';

const supportsBackgroundSync = false;

Future<void> startBackgroundSync({required void Function() openStore}) async {}

Future<void> runBackgroundSyncNow() async {}

Future<BackgroundStatus?> backgroundStatus() async => null;
