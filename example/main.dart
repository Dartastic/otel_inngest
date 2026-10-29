// Licensed under the Apache License, Version 2.0
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:otel_inngest/otel_inngest.dart';

/// Traces Inngest calls with OpenTelemetry.
///
/// `otel_inngest` depends on the OpenTelemetry API only, so the application
/// initializes an SDK once at startup. Wrap each Inngest call in
/// [tracedInngestSend]; the `invoke` callback makes the real call and reports what
/// came back, which is recorded on the span.
Future<void> main() async {
  await OTel.initialize(serviceName: 'inngest-example');

  // Traces a Inngest call.
  final inngestSendId = await tracedInngestSend<String>(
    eventName: 'order.created',
    env: 'example',
    userContext: {'source': 'example'},
    invoke: () async {
      // Make the Inngest call here, then report what it returned.
      const id = 'inngest_8f3a2c';
      return const InngestSendCallResult(
          value: id,
          result:
              InngestSendResult(eventIds: ['event_8f3a2c'], batchSize: 512));
    },
  );
  OTelLog.info('tracedInngestSend returned $inngestSendId');

  // Calls that should not be traced, such as health checks, run inside
  // runWithoutInngestInstrumentationAsync.
  await runWithoutInngestInstrumentationAsync(
    () => tracedInngestSend<String>(
      eventName: 'order.created',
      env: 'example',
      userContext: {'source': 'example'},
      invoke: () async {
        const id = 'inngest_8f3a2c';
        return const InngestSendCallResult(
            value: id,
            result:
                InngestSendResult(eventIds: ['event_8f3a2c'], batchSize: 512));
      },
    ),
  );

  await OTel.shutdown();
}
