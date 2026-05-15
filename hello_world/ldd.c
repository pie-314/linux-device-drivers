#include "linux/printk.h"
#include <linux/init.h>
#include <linux/module.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Pi");
MODULE_DESCRIPTION("Simple hello world");

static int init_pi(void) {
  printk("Hey i am pi");
  return 0;
}

static void exit_pi(void) { printk("bye"); }

module_init(init_pi);
module_exit(exit_pi);
