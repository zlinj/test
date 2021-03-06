#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#include "task.h"
#include "interact.h"

int main(int argc, char **argv)
{
    char *file = argv[1];
/*
    if (access(file, F_OK | R_OK) != 0) {
        fprintf(stderr, "invalid file: %s\n", file);
        return -1;
    }
*/
    char tips[MAX_TEXT_DFPATH] = {0};
    int num = 2, len = 0;
    char *p = tips;
    while (num < argc && (MAX_TEXT_DFPATH - 1 - (p - tips)) >= (len = strlen(argv[num]))) {
        strncpy(p, argv[num], len);
        p += len;
        *p++ = ' ';
        num++;
    }
    tips[p - tips - 1] = '\0';

    if (tshowimg(file, tips) == 0) {
        printf("%s\n", STR_TRUE);
        return 0;
    } else {
        printf("%s\n", STR_FALSE);
        return 1;
    }
}
