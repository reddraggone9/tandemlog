#include "time_observer.h"
#include <glib-unix.h>
#include <sys/timerfd.h>
#include <unistd.h>
#include <cerrno>
#include <cstdint>
#include <ctime>

namespace {
struct Observer {
  FlMethodChannel* channel;
  int fd = -1;
  guint source = 0;
  void Stop() {
    if (source) { g_source_remove(source); source = 0; }
    if (fd >= 0) { close(fd); fd = -1; }
  }
  bool Arm() {
    struct timespec now;
    if (clock_gettime(CLOCK_REALTIME, &now) != 0) return false;
    struct itimerspec timer = {};
    timer.it_value.tv_sec = now.tv_sec + 365 * 24 * 60 * 60;
    return timerfd_settime(fd, TFD_TIMER_ABSTIME | TFD_TIMER_CANCEL_ON_SET,
                          &timer, nullptr) == 0;
  }
  ~Observer() {
    Stop();
    fl_method_channel_set_method_call_handler(channel, nullptr, nullptr, nullptr);
    g_object_unref(channel);
  }
};
gboolean clock_changed(gint fd, GIOCondition condition, gpointer data) {
  auto* observer = static_cast<Observer*>(data);
  uint64_t ticks;
  const ssize_t count = read(fd, &ticks, sizeof(ticks));
  if ((count < 0 && errno == ECANCELED) || count == sizeof(ticks)) {
    fl_method_channel_invoke_method(observer->channel, "changed", nullptr,
                                   nullptr, nullptr, nullptr);
    if (observer->Arm()) return G_SOURCE_CONTINUE;
  } else if (!(condition & (G_IO_ERR | G_IO_HUP | G_IO_NVAL))) {
    return G_SOURCE_CONTINUE;
  }
  observer->source = 0;
  close(observer->fd); observer->fd = -1;
  return G_SOURCE_REMOVE;
}
void method_call(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* observer = static_cast<Observer*>(data);
  const gchar* method = fl_method_call_get_name(call);
  if (g_str_equal(method, "start")) {
    if (observer->fd < 0) {
      observer->fd = timerfd_create(CLOCK_REALTIME, TFD_NONBLOCK | TFD_CLOEXEC);
      if (observer->fd >= 0 && observer->Arm()) {
        observer->source = g_unix_fd_add(observer->fd,
          static_cast<GIOCondition>(G_IO_IN | G_IO_ERR | G_IO_HUP), clock_changed, observer);
      } else { observer->Stop(); }
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else if (g_str_equal(method, "stop")) {
    observer->Stop();
    fl_method_call_respond_success(call, nullptr, nullptr);
  } else { fl_method_call_respond_not_implemented(call, nullptr); }
}
}
void register_time_observer(FlView* view) {
  FlBinaryMessenger* messenger = fl_engine_get_binary_messenger(fl_view_get_engine(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
    messenger, "tandemlog/time", FL_METHOD_CODEC(codec));
  auto* observer = new Observer{FL_METHOD_CHANNEL(g_object_ref(channel))};
  fl_method_channel_set_method_call_handler(channel, method_call, observer, nullptr);
  // The view explicitly owns the observer/channel; no handler-reference cycle.
  g_object_set_data_full(G_OBJECT(view), "tandemlog-time-observer", observer,
    [](gpointer data) { delete static_cast<Observer*>(data); });
}
