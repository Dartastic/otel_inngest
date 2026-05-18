// Licensed under the Dartastic Pro Software License Agreement.
// Copyright 2025-2026 Mindful Software LLC d/b/a Dartastic.io, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';

import 'otel_inngest_suppression.dart';

const _tracerName = 'dartastic_otel_libs_inngest';

Tracer _tracer() => OTel.tracerProvider().getTracer(_tracerName);

class InngestSendResult {
  const InngestSendResult({this.eventIds, this.batchSize});

  /// `ids` field from the `POST /e/<key>` response.
  final List<String>? eventIds;
  final int? batchSize;
}

class InngestSendCallResult<T> {
  const InngestSendCallResult({required this.value, this.result});
  final T value;
  final InngestSendResult? result;
}

/// PRODUCER span around `inngest.send({ name, data })` — the event
/// fanout call that triggers matching durable functions.
Future<T> tracedInngestSend<T>({
  required String eventName,
  required Future<InngestSendCallResult<T>> Function() invoke,
  String? env,
  Map<String, String>? userContext,
}) async {
  if (inngestInstrumentationSuppressed()) {
    final r = await invoke();
    return r.value;
  }
  final m = <String, Object>{
    'messaging.system': 'inngest',
    'messaging.operation': 'publish',
    'messaging.destination.name': eventName,
    'inngest.event.name': eventName,
  };
  if (env != null) m['inngest.env'] = env;
  if (userContext != null) {
    for (final e in userContext.entries) {
      m['inngest.user.${e.key}'] = e.value;
    }
  }

  final span = _tracer().startSpan(
    'inngest send $eventName',
    kind: SpanKind.producer,
    attributes: OTel.attributesFromMap(m),
  );
  try {
    final r = await invoke();
    if (r.result != null) {
      final extras = <Attribute<Object>>[];
      if (r.result!.eventIds != null && r.result!.eventIds!.isNotEmpty) {
        extras.add(OTel.attributeString(
          'inngest.event.ids',
          r.result!.eventIds!.join(','),
        ));
        if (r.result!.eventIds!.length == 1) {
          extras.add(OTel.attributeString(
            'messaging.message.id',
            r.result!.eventIds!.first,
          ));
        }
      }
      if (r.result!.batchSize != null) {
        extras.add(OTel.attributeInt(
          'messaging.batch.message_count',
          r.result!.batchSize!,
        ));
      }
      if (extras.isNotEmpty) span.addAttributes(OTel.attributes(extras));
    }
    return r.value;
  } catch (e, st) {
    span.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        e.runtimeType.toString(),
      ),
    ]));
    span.recordException(e, stackTrace: st);
    span.setStatus(SpanStatusCode.Error, e.toString());
    rethrow;
  } finally {
    span.end();
  }
}
