#ifndef LEGATO_CONFIG_H
#define LEGATO_CONFIG_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LEGATO_PATH_MAX 1024
#define LEGATO_DIRS_MAX 32

/*
 * The desktop client's settings, as kept in legato.yaml:
 *
 *   music_dirs:
 *     - /Users/me/Music/Legato
 *   volume: 80
 *
 * music_dirs are the folders Legato looks after: it finds the music in them and keeps the tags in those files up to date.
 */
typedef struct {
    char music_dirs[LEGATO_DIRS_MAX][LEGATO_PATH_MAX];
    int  music_dir_count;
    int  volume;             /* 0..100 */
} legato_config;

/* Fill cfg with built-in defaults (no music folders: the person chooses them). */
void legato_config_defaults(legato_config *cfg);

/*
 * Write the config file path into buf:
 *   Linux/macOS: $XDG_CONFIG_HOME/legato/legato.yaml, else ~/.config/legato/legato.yaml
 *   Windows:     %APPDATA%\legato\legato.yaml
 * Returns 0 on success, -1 if the path can't be determined or doesn't fit.
 */
int legato_config_path(char *buf, size_t len);

/*
 * Load the config file into cfg, starting from defaults. Unknown keys are
 * ignored. If the file doesn't exist it is created with the defaults.
 * Returns 0 on success, -1 on error (cfg still holds usable values).
 */
int legato_config_load(legato_config *cfg);

/* Write cfg to the config file, creating the directory if needed. 0 / -1. */
int legato_config_save(const legato_config *cfg);

/* Add a music folder. 0 on success, 1 if it is already there, -1 if the list is full or the path doesn't fit. */
int legato_config_add_dir(legato_config *cfg, const char *dir);

/* Remove the music folder at index. 0 / -1. */
int legato_config_remove_dir(legato_config *cfg, int index);

#ifdef __cplusplus
}
#endif

#endif
