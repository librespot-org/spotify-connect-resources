/* useful hex manipulation routine header */
/* Copyright C Qualcomm Inc 1997 */
/* $Id: hexlib.h 333 2005-04-13 05:35:54Z mwp $ */

extern int	nerrors;

int hexprint(const char *, unsigned char *, int n);
int hexread(unsigned char *, char *, int n);
int hexcheck(unsigned char *, char *, int n);
int hexbulk(unsigned char *, int n);
