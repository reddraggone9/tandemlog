#define _GNU_SOURCE
#include <gtk/gtk.h>
#include <dlfcn.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>

typedef struct {
  const char* name;
  GObject* object;
  gboolean destroyed;
  gboolean finalized;
  void (*original_finalize)(GObject*);
} Watch;
static Watch watches[4] = {{"window", NULL, FALSE, FALSE, NULL},
                           {"view", NULL, FALSE, FALSE, NULL},
                           {"engine", NULL, FALSE, FALSE, NULL},
                           {"renderer", NULL, FALSE, FALSE, NULL}};
static void emit(const char* event, const char* object) {
  fprintf(stderr, "TANDEMLOG_LIFECYCLE_PROBE event=%s object=%s thread=%ld\n",
          event, object, (long)syscall(SYS_gettid));
}
// A weak notification observes dispose(), not finalize(): GTK can dispose a
// retained renderer while its compositor remains alive. Observe the actual
// type finalizer and delegate it unchanged, without retaining the object.
static void finalized(unsigned index, GObject* object) {
  Watch* entry = &watches[index];
  gboolean observed = entry->object == object;
  entry->original_finalize(object);
  if (observed) {
    entry->finalized = TRUE;
    entry->object = NULL;
    emit("finalized", entry->name);
  }
}
static void finalize_window(GObject* object) { finalized(0, object); }
static void finalize_view(GObject* object) { finalized(1, object); }
static void finalize_engine(GObject* object) { finalized(2, object); }
static void finalize_renderer(GObject* object) { finalized(3, object); }
static void (*finalizers[4])(GObject*) = {
    finalize_window, finalize_view, finalize_engine, finalize_renderer};
static void destroyed(GtkWidget* object, gpointer data) {
  (void)object;
  Watch* watch = data;
  watch->destroyed = TRUE;
  emit("destroyed", watch->name);
}
static void watch(unsigned index, GObject* object, gboolean widget) {
  Watch* entry = &watches[index];
  if (entry->object || entry->finalized || object == NULL) return;
  entry->object = object;  // Observation only: never retain or dispose it.
  GObjectClass* klass = G_OBJECT_GET_CLASS(object);
  entry->original_finalize = klass->finalize;
  klass->finalize = finalizers[index];
  if (widget) g_signal_connect(object, "destroy", G_CALLBACK(destroyed), entry);
  emit("watch", entry->name);
}
static void watch_renderer(GtkWidget* widget, gpointer data) {
  (void)data;
  if (g_strcmp0(G_OBJECT_TYPE_NAME(widget), "FlViewRenderer") == 0) {
    watch(3, G_OBJECT(widget), TRUE);
  }
  if (GTK_IS_CONTAINER(widget)) {
    gtk_container_forall(GTK_CONTAINER(widget), watch_renderer, NULL);
  }
}
void gtk_window_set_application(GtkWindow* window, GtkApplication* application) {
  typedef void (*Real)(GtkWindow*, GtkApplication*);
  Real real = (Real)dlsym(RTLD_NEXT, "gtk_window_set_application");
  if (application == NULL && watches[0].object == NULL && !watches[0].finalized) {
    watch(0, G_OBJECT(window), TRUE);
    GtkWidget* child = gtk_bin_get_child(GTK_BIN(window));
    if (child != NULL && g_strcmp0(G_OBJECT_TYPE_NAME(child), "FlView") == 0) {
      watch(1, G_OBJECT(child), TRUE);
      typedef gpointer (*GetEngine)(gpointer);
      GetEngine get_engine = (GetEngine)dlsym(RTLD_DEFAULT, "fl_view_get_engine");
      if (get_engine != NULL) watch(2, G_OBJECT(get_engine(child)), FALSE);
      watch_renderer(child, NULL);
    }
    emit("detach", "window");
  }
  real(window, application);
}
int g_application_run(GApplication* application, int argc, char** argv) {
  typedef int (*Real)(GApplication*, int, char**);
  Real real = (Real)dlsym(RTLD_NEXT, "g_application_run");
  int result = real(application, argc, argv);
  for (unsigned i = 0; i < 4; ++i) {
    fprintf(stderr, "TANDEMLOG_LIFECYCLE_PROBE event=run-return object=%s "
                    "watched=%d destroyed=%d finalized=%d thread=%ld\n",
            watches[i].name, watches[i].object != NULL || watches[i].finalized,
            watches[i].destroyed, watches[i].finalized,
            (long)syscall(SYS_gettid));
  }
  return result;
}
