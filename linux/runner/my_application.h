#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(MyApplication,
                     my_application,
                     MY,
                     APPLICATION,
                     GtkApplication)

/**
 * my_application_new:
 *
 * Creates a new Flutter-based application.
 *
 * Returns: a new #MyApplication.
 */
MyApplication* my_application_new();

// Queried after the application loop returns; incomplete engine disposal must
// not be reported as successful normal exit.
gboolean my_application_shutdown_complete(MyApplication* self);

#endif  // FLUTTER_MY_APPLICATION_H_
