// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:dartastic_opentelemetry/testing.dart';
import 'package:otel_inngest/otel_inngest.dart';
import 'package:test/test.dart';

void main() {
  late TestHarness harness;
  late InMemorySpanExporter spans;

  setUpAll(() async {
    harness = await maybeInitializeOtelForTest(
      serviceName: 'otel_inngest-test',
    );
    spans = harness.spans;
  });

  setUp(() => harness.clear());

  Map<String, Object> attrsOf(Span s) =>
      {for (final a in s.attributes.toList()) a.key: a.value};

  test('send records PRODUCER span with messaging.* + inngest.*', () async {
    await tracedInngestSend<String>(
      eventName: 'user.signup',
      env: 'prod',
      userContext: const {'id': 'u-123', 'plan': 'pro'},
      invoke: () async => const InngestSendCallResult(
        value: 'ok',
        result: InngestSendResult(eventIds: ['evt-1']),
      ),
    );
    final span = spans.findSpanByName('inngest send user.signup')!;
    expect(span.kind, SpanKind.producer);
    final a = attrsOf(span);
    expect(a['messaging.system'], 'inngest');
    expect(a['messaging.destination.name'], 'user.signup');
    expect(a['inngest.env'], 'prod');
    expect(a['inngest.user.id'], 'u-123');
    expect(a['inngest.user.plan'], 'pro');
    expect(a['messaging.message.id'], 'evt-1');
  });

  test('batch send records batch count + ids csv', () async {
    await tracedInngestSend<String>(
      eventName: 'orders.batch',
      invoke: () async => const InngestSendCallResult(
        value: 'ok',
        result: InngestSendResult(eventIds: ['e1', 'e2', 'e3'], batchSize: 3),
      ),
    );
    final a = attrsOf(spans.findSpanByName('inngest send orders.batch')!);
    expect(a['messaging.batch.message_count'], 3);
    expect(a['inngest.event.ids'], 'e1,e2,e3');
  });

  test('suppression skips spans', () async {
    await runWithoutInngestInstrumentationAsync(() async {
      await tracedInngestSend<String>(
        eventName: 'x',
        invoke: () async => const InngestSendCallResult(value: 'v'),
      );
    });
    expect(spans.findSpansStartingWith('inngest '), isEmpty);
  });
}
