import 'package:integration_test/integration_test_driver.dart';

/// Writes the perf test's report to build/perf_summary.json.
Future<void> main() => integrationDriver(
  responseDataCallback: (data) =>
      writeResponseData(data, testOutputFilename: 'perf_summary'),
);
