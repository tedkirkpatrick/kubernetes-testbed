'''
SFU CMPT 756
Tracing for sample application

Taken from https://github.com/istio/istio/blob/master/samples/bookinfo/src/productpage/productpage.py
with some modification.
'''

# Installed packages
from flask import _request_ctx_stack as stack

from jaeger_client import ConstSampler, Tracer
from jaeger_client.codecs import B3Codec
from jaeger_client.reporter import NullReporter

from opentracing.ext import tags
from opentracing.propagation import Format
from opentracing_instrumentation.request_context import get_current_span, span_in_context

#
# A note on distributed tracing:
#
# Although Istio proxies are able to automatically send spans, they need some
# hints to tie together the entire trace. Applications need to propagate the
# appropriate HTTP headers so that when the proxies send span information, the
# spans can be correlated correctly into a single trace.
#
# To do this, an application needs to collect and propagate headers from the
# incoming request to any outgoing requests. The choice of headers to propagate
# is determined by the trace configuration used. See getForwardHeaders for
# the different header options.
#
# This example code uses OpenTracing (http://opentracing.io/) to propagate
# the 'b3' (zipkin) headers. Using OpenTracing for this is not a requirement.
# Using OpenTracing allows you to add application-specific tracing later on,
# but you can just manually forward the headers if you prefer.
#
# The OpenTracing example here is very basic. It only forwards headers. It is
# intended as a reference to help people get started, eg how to create spans,
# extract/inject context, etc.


class SimpleTracer:
    '''A very basic OpenTracing tracer, with null reporter'''


    def __init__(self, sname):
        self.tracer = Tracer(
            one_span_per_rpc=True,
            service_name=sname,
            reporter=NullReporter(),
            sampler=ConstSampler(decision=True),
            extra_codecs={Format.HTTP_HEADERS: B3Codec()}
            )


    def trace(self):
        '''
        Decorator that creates opentracing span from incoming b3 headers
        '''
        def decorator(f):
            def wrapper(*args, **kwargs):
                global stack
                request = stack.top.request
                try:
                    # Create a new span context, reading in values (traceid,
                    # spanid, etc) from the incoming x-b3-*** headers.
                    span_ctx = self.tracer.extract(
                        Format.HTTP_HEADERS,
                        dict(request.headers)
                    )
                    # Note: this tag means that the span will *not* be
                    # a child span. It will use the incoming traceid and
                    # spanid. We do this to propagate the headers verbatim.
                    rpc_tag = {tags.SPAN_KIND: tags.SPAN_KIND_RPC_SERVER}
                    span = self.tracer.start_span(
                        operation_name='op', child_of=span_ctx, tags=rpc_tag
                    )
                except Exception as e:
                    # We failed to create a context, possibly due to no
                    # incoming x-b3-*** headers. Start a fresh span.
                    # Note: This is a fallback only, and will create fresh
                    # headers, not propagate headers.
                    span = self.tracer.start_span('op')
                with span_in_context(span):
                    r = f(*args, **kwargs)
                    return r
            wrapper.__name__ = f.__name__
            return wrapper
        return decorator


    def getForwardHeaders(self, request):
        '''
        Return the headers that should be forwarded to subservices.

        This function currently forwards instances of tracing headers
        for a much wider range of tracing tools than are used in
        this course. If those headers are not present, nothing
        happens other than a bit of wasted computation here.

        At some point, we should pare down the list to only those
        headers needed by the tools used in class.

        The final block, "Application-specific", includes headers
        not needed for tracing but that our application requires to
        be forwarded.
        '''
        headers = {}

        # x-b3-*** headers can be populated using the opentracing span
        span = get_current_span()
        carrier = {}
        self.tracer.inject(
            span_context=span.context,
            format=Format.HTTP_HEADERS,
            carrier=carrier)

        headers.update(carrier)

        # CMPT 756 --- COMMENTED OUT FROM bookinfo
        # We handle other (non x-b3-***) headers manually
        #if 'user' in session:
        #    headers['end-user'] = session['user']

        # Keep this in sync with the headers in details and reviews.
        incoming_headers = [
            # All applications should propagate x-request-id. This header is
            # included in access log statements and is used for consistent trace
            # sampling and log sampling decisions in Istio.
            'x-request-id',

            # Lightstep tracing header. Propagate this if you use lightstep tracing
            # in Istio (see
            # https://istio.io/latest/docs/tasks/observability/distributed-tracing/lightstep/)
            # Note: this should probably be changed to use B3 or W3C TRACE_CONTEXT.
            # Lightstep recommends using B3 or TRACE_CONTEXT and most application
            # libraries from lightstep do not support x-ot-span-context.
            'x-ot-span-context',

            # Datadog tracing header. Propagate these headers if you use Datadog
            # tracing.
            'x-datadog-trace-id',
            'x-datadog-parent-id',
            'x-datadog-sampling-priority',

            # W3C Trace Context. Compatible with OpenCensusAgent and Stackdriver Istio
            # configurations.
            'traceparent',
            'tracestate',

            # Cloud trace context. Compatible with OpenCensusAgent and Stackdriver Istio
            # configurations.
            'x-cloud-trace-context',

            # Grpc binary trace context. Compatible with OpenCensusAgent nad
            # Stackdriver Istio configurations.
            'grpc-trace-bin',

            # b3 trace headers. Compatible with Zipkin, OpenCensusAgent, and
            # Stackdriver Istio configurations. Commented out since they are
            # propagated by the OpenTracing tracer above.
            # 'x-b3-traceid',
            # 'x-b3-spanid',
            # 'x-b3-parentspanid',
            # 'x-b3-sampled',
            # 'x-b3-flags',

            # Application-specific headers to forward.
            'user-agent',
            'Authorization', # CMPT 756
        ]
        # For Zipkin, always propagate b3 headers.
        # For Lightstep, always propagate the x-ot-span-context header.
        # For Datadog, propagate the corresponding datadog headers.
        # For OpenCensusAgent and Stackdriver configurations, you can choose any
        # set of compatible headers to propagate within your application. For
        # example, you can propagate b3 headers or W3C trace context headers with
        # the same result. This can also allow you to translate between context
        # propagation mechanisms between different applications.

        for ihdr in incoming_headers:
            val = request.headers.get(ihdr)
            if val is not None:
                headers[ihdr] = val

        return headers
