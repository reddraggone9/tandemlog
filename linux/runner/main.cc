#include "my_application.h"

int main(int argc, char** argv) {
  g_autoptr(MyApplication) app = my_application_new();
  int status = g_application_run(G_APPLICATION(app), argc, argv);
  return my_application_shutdown_complete(app) ? status : 1;
}
