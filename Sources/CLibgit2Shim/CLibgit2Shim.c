#include "CLibgit2Shim.h"
#include <git2/common.h>

int swiftports_libgit2_set_search_path(int level, const char *path) {
    return git_libgit2_opts(GIT_OPT_SET_SEARCH_PATH, level, path);
}

int swiftports_libgit2_set_homedir(const char *path) {
    return git_libgit2_opts(GIT_OPT_SET_HOMEDIR, path);
}
