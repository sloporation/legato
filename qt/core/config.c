#include "config.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <yaml.h>

#ifdef _WIN32
#include <direct.h>
#define PATH_SEP '\\'
#define make_dir(p) _mkdir(p)
#else
#define PATH_SEP '/'
#define make_dir(p) mkdir((p), 0755)
#endif

void legato_config_defaults(legato_config *cfg)
{
    cfg->music_dir_count = 0;
    cfg->volume = 80;
}

int legato_config_add_dir(legato_config *cfg, const char *dir)
{
    int i;

    for (i = 0; i < cfg->music_dir_count; i++)
        if (strcmp(cfg->music_dirs[i], dir) == 0)
            return 1;
    if (cfg->music_dir_count >= LEGATO_DIRS_MAX || strlen(dir) >= LEGATO_PATH_MAX)
        return -1;
    snprintf(cfg->music_dirs[cfg->music_dir_count++], LEGATO_PATH_MAX, "%s", dir);
    return 0;
}

int legato_config_remove_dir(legato_config *cfg, int index)
{
    if (index < 0 || index >= cfg->music_dir_count)
        return -1;
    memmove(cfg->music_dirs[index], cfg->music_dirs[index + 1],
            (size_t)(cfg->music_dir_count - index - 1) * LEGATO_PATH_MAX);
    cfg->music_dir_count--;
    return 0;
}

/* Directory holding the config file (no trailing separator). */
static int config_dir(char *buf, size_t len)
{
    int n;
#ifdef _WIN32
    const char *appdata = getenv("APPDATA");
    if (!appdata || !*appdata)
        return -1;
    n = snprintf(buf, len, "%s\\legato", appdata);
#else
    const char *xdg = getenv("XDG_CONFIG_HOME");
    const char *home = getenv("HOME");
    if (xdg && xdg[0] == '/')
        n = snprintf(buf, len, "%s/legato", xdg);
    else if (home && *home)
        n = snprintf(buf, len, "%s/.config/legato", home);
    else
        return -1;
#endif
    return (n < 0 || (size_t)n >= len) ? -1 : 0;
}

int legato_config_path(char *buf, size_t len)
{
    char dir[LEGATO_PATH_MAX];
    int n;

    if (config_dir(dir, sizeof dir) != 0)
        return -1;
    n = snprintf(buf, len, "%s%clegato.yaml", dir, PATH_SEP);
    return (n < 0 || (size_t)n >= len) ? -1 : 0;
}

/* mkdir -p for the config directory (and its parent, ~/.config). */
static int ensure_dir(void)
{
    char dir[LEGATO_PATH_MAX];
    char *p;

    if (config_dir(dir, sizeof dir) != 0)
        return -1;
    for (p = dir + 1; *p; p++) {
        if (*p == PATH_SEP) {
            *p = '\0';
            make_dir(dir); /* errors (e.g. already exists) surface at the final mkdir */
            *p = PATH_SEP;
        }
    }
    if (make_dir(dir) != 0 && errno != EEXIST)
        return -1;
    return 0;
}

static void apply(legato_config *cfg, const char *key, const char *value)
{
    if (strcmp(key, "volume") == 0) {
        int v = atoi(value);
        cfg->volume = v < 0 ? 0 : v > 100 ? 100 : v;
    }
}

int legato_config_load(legato_config *cfg)
{
    char path[LEGATO_PATH_MAX];
    FILE *f;
    yaml_parser_t parser;
    yaml_event_t ev;
    char key[64];
    int have_key = 0, depth = 0, done = 0, rc = 0;
    int in_dirs = 0; /* inside the music_dirs list */

    legato_config_defaults(cfg);
    if (legato_config_path(path, sizeof path) != 0)
        return -1;

    f = fopen(path, "rb");
    if (!f) {
        if (errno == ENOENT)
            return legato_config_save(cfg);
        return -1;
    }

    yaml_parser_initialize(&parser);
    yaml_parser_set_input_file(&parser, f);

    /* A "key: value" mapping (events alternate key scalar, value scalar), where music_dirs is a list of scalars. */
    while (!done) {
        if (!yaml_parser_parse(&parser, &ev)) {
            rc = -1;
            break;
        }
        switch (ev.type) {
        case YAML_MAPPING_START_EVENT:
        case YAML_SEQUENCE_START_EVENT:
            in_dirs = ev.type == YAML_SEQUENCE_START_EVENT && depth == 1 && have_key && strcmp(key, "music_dirs") == 0;
            depth++;
            have_key = 0;
            break;
        case YAML_MAPPING_END_EVENT:
        case YAML_SEQUENCE_END_EVENT:
            in_dirs = 0;
            depth--;
            break;
        case YAML_SCALAR_EVENT:
            if (in_dirs && depth == 2) {
                if (ev.data.scalar.length > 0)
                    legato_config_add_dir(cfg, (const char *)ev.data.scalar.value);
                break;
            }
            if (depth != 1)
                break; /* ignore nested values */
            if (!have_key) {
                snprintf(key, sizeof key, "%s", (const char *)ev.data.scalar.value);
                have_key = 1;
            } else {
                apply(cfg, key, (const char *)ev.data.scalar.value);
                have_key = 0;
            }
            break;
        case YAML_STREAM_END_EVENT:
            done = 1;
            break;
        default:
            break;
        }
        yaml_event_delete(&ev);
    }

    yaml_parser_delete(&parser);
    fclose(f);
    return rc;
}

/* Emit one scalar (quoted only if it needs to be). */
static int emit_scalar(yaml_emitter_t *em, const char *value)
{
    yaml_event_t ev;

    yaml_scalar_event_initialize(&ev, NULL, NULL, (yaml_char_t *)value,
                                 -1, 1, 1, YAML_ANY_SCALAR_STYLE);
    return yaml_emitter_emit(em, &ev) ? 0 : -1;
}

/* Emit one "key: value" pair. */
static int emit_pair(yaml_emitter_t *em, const char *key, const char *value)
{
    return emit_scalar(em, key) == 0 && emit_scalar(em, value) == 0 ? 0 : -1;
}

int legato_config_save(const legato_config *cfg)
{
    char path[LEGATO_PATH_MAX];
    char vol[16];
    FILE *f;
    yaml_emitter_t em;
    yaml_event_t ev;
    int i, rc = -1;

    if (legato_config_path(path, sizeof path) != 0 || ensure_dir() != 0)
        return -1;
    f = fopen(path, "wb");
    if (!f)
        return -1;

    yaml_emitter_initialize(&em);
    yaml_emitter_set_output_file(&em, f);

    snprintf(vol, sizeof vol, "%d", cfg->volume);

    yaml_stream_start_event_initialize(&ev, YAML_UTF8_ENCODING);
    if (!yaml_emitter_emit(&em, &ev)) goto out;
    yaml_document_start_event_initialize(&ev, NULL, NULL, NULL, 1);
    if (!yaml_emitter_emit(&em, &ev)) goto out;
    yaml_mapping_start_event_initialize(&ev, NULL, NULL, 1, YAML_BLOCK_MAPPING_STYLE);
    if (!yaml_emitter_emit(&em, &ev)) goto out;

    if (emit_scalar(&em, "music_dirs") != 0) goto out;
    yaml_sequence_start_event_initialize(&ev, NULL, NULL, 1, YAML_BLOCK_SEQUENCE_STYLE);
    if (!yaml_emitter_emit(&em, &ev)) goto out;
    for (i = 0; i < cfg->music_dir_count; i++)
        if (emit_scalar(&em, cfg->music_dirs[i]) != 0) goto out;
    yaml_sequence_end_event_initialize(&ev);
    if (!yaml_emitter_emit(&em, &ev)) goto out;
    if (emit_pair(&em, "volume", vol) != 0) goto out;

    yaml_mapping_end_event_initialize(&ev);
    if (!yaml_emitter_emit(&em, &ev)) goto out;
    yaml_document_end_event_initialize(&ev, 1);
    if (!yaml_emitter_emit(&em, &ev)) goto out;
    yaml_stream_end_event_initialize(&ev);
    if (!yaml_emitter_emit(&em, &ev)) goto out;
    rc = 0;

out:
    yaml_emitter_delete(&em);
    if (fclose(f) != 0)
        rc = -1;
    return rc;
}
