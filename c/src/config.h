#ifndef CCC_CONFIG_H
#define CCC_CONFIG_H

#include "parser.h"

int ccc_find_config_path(
    const char *ccc_config,
    const char *xdg_config_home,
    const char *home,
    char *out_path,
    size_t out_max
);

int ccc_load_config(const char *path, CccConfig *out);

#endif
