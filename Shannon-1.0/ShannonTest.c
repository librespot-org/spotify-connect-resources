/* $Id: shntest.c 442 2006-05-12 23:22:21Z ggr $ */
/*
 * Test harness for Shannon
 *
 * Copyright C 2006, Qualcomm Inc. Written by Greg Rose
 */

/*
THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE AND AGAINST
INFRINGEMENT ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include "Shannon.h"		/* interface definitions */

shn_ctx ctx;

/* testing and timing harness */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "hexlib.h"

/* mostly for debugging, print the LFSR contents. */
int	v = 0; /* disables debug stuff */
int	bulkflag = 0; /* bulk binary output for testing */
void
printLFSR(const char *s, WORD R[])
{
    register int	i;

    if (!v) return;
    printf("%s\n", s);
    for (i = 0; i < N; ++i) {
	printf("%*s%08x\n", i*4, "", R[i]);
    }
}

/* test vectors */
UCHAR	*testkey = (UCHAR *)"test key 128bits";
UCHAR	*testframe = (UCHAR *)"\0\0\0\0";

#define TESTSIZE 20
#define INPUTSIZE 100
#define STREAMTEST 1000000
#define ITERATIONS 999999
char    *testout =
	"4d 7e d3 9c b6 95 d9 6a cf 52 97 70 ec 7d cc be ae 2b 6f 8c";
char	*streamout =
	"27 01 9f c8 84 bb 09 05 ea 08 c9 b5 5f 20 7b 5d 34 80 b4 a3";
char	*macout =
	"00 13 88 e9 6b a7 8e 74 4e b0 b0 30 44 25 c0 90 36 dc 80 1a";
char	*zeros = 
	"00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00";
char    *iterout =
	"4e 00 9e 3f 99 3e 3a 1e b9 cb 28 11 a2 e9 09 69 a8 9e 1e f3";
char	*nonceout = 
	"ca a7 23 3e 5c c1 67 64 3a 11 62 25 71 6e 75 28 18 c1 d6 4f";
char	*hellmac = 
	"2c ac f6 55 bc 33 09 b5 d3 9b 82 7e 27 fa cf 97 de 83 0f e1";

UCHAR	testbuf[STREAMTEST + INPUTSIZE];
UCHAR	macbuf[INPUTSIZE];
UCHAR	mac[TESTSIZE];
UCHAR	bigbuf[1024*1024];

void
test_shn(int quick)
{
    int			i;
    unsigned char	ha, he, hm, hc; /* hell test variables */

    /* basic test */
    memset(testbuf, '\0', sizeof testbuf);
    shn_key(&ctx, testkey, strlen((char *)testkey));
    printLFSR("Saved LFSR", ctx.initR);
    /* check endian-ness */
    if (ctx.initR[0] == 0x55bf8df5)
	printf("It is probable that byte ordering is incorrect.\n");
    shn_nonce(&ctx, testframe, 4);
    shn_stream(&ctx, testbuf, INPUTSIZE);
    hexprint("one chunk", testbuf, TESTSIZE);
    hexcheck(testbuf, testout, TESTSIZE);

    /* now redo that test, byte-at-a-time */
    memset(testbuf, '\0', sizeof testbuf);
    shn_nonce(&ctx, testframe, 4);
    for (i = 0; i < INPUTSIZE; ++i)
	shn_stream(&ctx, testbuf+i, 1);
    hexprint("single bytes", testbuf, TESTSIZE);
    hexcheck(testbuf, testout, TESTSIZE);

    /* generate and test more of the same stream */
    shn_stream(&ctx, testbuf + INPUTSIZE, STREAMTEST);
    hexprint("STREAMTEST", testbuf + STREAMTEST, TESTSIZE);
    hexcheck(testbuf + STREAMTEST, streamout, TESTSIZE);

    /* generate and check a MAC of an empty buffer */
    memset(macbuf, '\0', sizeof macbuf);
    shn_nonce(&ctx, testframe, 4);
    shn_maconly(&ctx, macbuf, sizeof macbuf);
    shn_finish(&ctx, mac, sizeof mac);
    hexprint("MAC test", mac, sizeof mac);
    hexcheck(mac, macout, sizeof mac);

    /* now redo that test, byte-at-a-time */
    memset(macbuf, '\0', sizeof macbuf);
    shn_nonce(&ctx, testframe, 4);
    for (i = 0; i < sizeof macbuf; ++i)
	shn_maconly(&ctx, macbuf+i, 1);
    shn_finish(&ctx, mac, sizeof mac);
    hexprint("MAC bytes", mac, sizeof mac);
    hexcheck(mac, macout, sizeof mac);

    /* encrypt and MAC an empty buffer */
    memset(macbuf, '\0', sizeof macbuf);
    shn_nonce(&ctx, testframe, 4);
    shn_encrypt(&ctx, macbuf, sizeof macbuf);
    hexprint("MAC+enc test", macbuf, TESTSIZE);
    hexcheck(macbuf, testout, TESTSIZE);
    shn_finish(&ctx, mac, sizeof mac);
    hexprint("final MAC", mac, sizeof mac);
    hexcheck(mac, macout, sizeof mac);

    /* now decrypt it and verify the MAC */
    shn_nonce(&ctx, testframe, 4);
    shn_decrypt(&ctx, macbuf, sizeof macbuf);
    hexprint("MAC+dec test", macbuf, TESTSIZE);
    hexcheck(macbuf, zeros, TESTSIZE);
    shn_finish(&ctx, mac, sizeof mac);
    hexprint("final MAC", mac, sizeof mac);
    hexcheck(mac, macout, sizeof mac);

    /* redo those tests, byte-at-a-time */
    memset(macbuf, '\0', sizeof macbuf);
    shn_nonce(&ctx, testframe, 4);
    for (i = 0; i < sizeof macbuf; ++i)
	shn_encrypt(&ctx, macbuf+i, 1);
    hexprint("M+e bytes", macbuf, TESTSIZE);
    hexcheck(macbuf, testout, TESTSIZE);
    shn_finish(&ctx, mac, sizeof mac);
    hexprint("final MAC", mac, sizeof mac);
    hexcheck(mac, macout, sizeof mac);
    shn_nonce(&ctx, testframe, 4);
    for (i = 0; i < sizeof macbuf; ++i)
	shn_decrypt(&ctx, macbuf+i, 1);
    hexprint("M+d bytes", macbuf, TESTSIZE);
    hexcheck(macbuf, zeros, TESTSIZE);
    shn_finish(&ctx, mac, sizeof mac);
    hexprint("final MAC", mac, sizeof mac);
    hexcheck(mac, macout, sizeof mac);

    if (quick)
	return;

    /* test many times iterated */
    for (i = 0; i < ITERATIONS; ++i) {
	if (i % 500 == 0 && !v)
	    printf("%6d\r", i), fflush(stdout);
	shn_key(&ctx, testbuf, TESTSIZE);
	shn_stream(&ctx, testbuf, TESTSIZE);
    }
    printf("1000000\n");
    hexprint("iterated", testbuf, TESTSIZE);
    hexcheck(testbuf, iterout, TESTSIZE);

    /* test many times iterated through the nonce */
    shn_key(&ctx, testkey, strlen((char *)testkey));
    shn_nonce(&ctx, NULL, 0);
    memset(testbuf, '\0', sizeof testbuf);
    shn_stream(&ctx, testbuf, TESTSIZE);
    for (i = 0; i < ITERATIONS; ++i) {
	if (i % 500 == 0 && !v)
	    printf("%6d\r", i), fflush(stdout);
	shn_nonce(&ctx, testbuf, 4);
	shn_stream(&ctx, testbuf, 4);
    }
    printf("1000000\n");
    hexprint("nonce test", testbuf, TESTSIZE);
    hexcheck(testbuf, nonceout, TESTSIZE);

    /* now the test vector from hell --
     * Start with a large, zero'd buffer, and a MAC buffer.
     * Iterate 1000000 times encrypting/decrypting/macing under control
     * of the output.
     */
    shn_key(&ctx, testkey, strlen((char *)testkey));
    memset(testbuf, '\0', sizeof testbuf);
    memset(mac, '\0', TESTSIZE);
    for (i = 0; i < ITERATIONS+1; ++i) {
	if (i % 500 == 0 && !v)
	    printf("%6d\r", i), fflush(stdout);
	hm = 5 + mac[0] % (TESTSIZE - 4);
	he = mac[1];
	ha = mac[2];
	hc = mac[3] & 0x03;
	switch (hc) {
	case 0: /* MAC only, then encrypt */
	    if (v) printf("mac %3d, enc %3d: ", ha, he);
	    shn_maconly(&ctx, testbuf, ha);
	    shn_encrypt(&ctx, testbuf+ha, he);
	    break;
	case 1: /* Encrypt then MAC */
	    if (v) printf("enc %3d, mac %3d: ", he, ha);
	    shn_encrypt(&ctx, testbuf, he);
	    shn_maconly(&ctx, testbuf+he, ha);
	    break;
	case 2: /* MAC only, then decrypt */
	    if (v) printf("mac %3d, dec %3d: ", ha, he);
	    shn_maconly(&ctx, testbuf, ha);
	    shn_decrypt(&ctx, testbuf+ha, he);
	    break;
	case 3: /* decrypt then MAC */
	    if (v) printf("dec %3d, mac %3d: ", he, ha);
	    shn_decrypt(&ctx, testbuf, he);
	    shn_maconly(&ctx, testbuf+he, ha);
	    break;
	}
	shn_finish(&ctx, mac, hm);
	if (v) hexprint("MAC", mac, hm);
	shn_nonce(&ctx, mac, TESTSIZE);
    }
    printf("1000000\n");
    hexbulk(testbuf, 510);
    hexprint("hell MAC", mac, TESTSIZE);
    hexcheck(mac, hellmac, TESTSIZE);
}

#define BLOCKSIZE	1600	/* for MAC-style tests */
#define MACSIZE		8
/* Perform various timing tests
 */
void
time_shn(void)
{
    long	i;
    clock_t	t;
    WORD	k[4] = { 0, 0, 0, 0 };

    test_shn(1);
    shn_key(&ctx, testkey, strlen((char *)testkey));
    shn_nonce(&ctx, (unsigned char *)"", 0);

    /* test stream generation speed */
    t = clock();
    for (i = 0; i < 200000000; ) {
	i += sizeof bigbuf;
	shn_stream(&ctx, bigbuf, sizeof bigbuf);
    }
    t = clock() - t;
    printf("%f Mbyte per second single stream encryption\n",
	(((double)i/((double)t / (double)CLOCKS_PER_SEC))) / 1000000.0);

    /* test packet encryption speed */
    t = clock();
    for (i = 0; i < 200000000; ) {
	shn_nonce(&ctx, testframe, 4);
	shn_stream(&ctx, bigbuf, BLOCKSIZE);
	i += BLOCKSIZE;
    }
    t = clock() - t;
    printf("%f Mbyte per second encrypt %d-byte blocks\n",
	(((double)i/((double)t / (double)CLOCKS_PER_SEC))) / 1000000.0,
	BLOCKSIZE);

    /* test MAC generation speed */
    t = clock();
    for (i = 0; i < 200000000; ) {
	shn_nonce(&ctx, testframe, 4);
	shn_maconly(&ctx, bigbuf, BLOCKSIZE);
	shn_finish(&ctx, macbuf, MACSIZE);
	i += BLOCKSIZE;
    }
    t = clock() - t;
    printf("%f Mbyte per second MAC %d-byte blocks %d-bit MAC\n",
	(((double)i/((double)t / (double)CLOCKS_PER_SEC))) / 1000000.0,
	BLOCKSIZE, MACSIZE*8);

    /* test combined encryption speed */
    t = clock();
    for (i = 0; i < 200000000; ) {
	shn_nonce(&ctx, testframe, 4);
	shn_encrypt(&ctx, bigbuf, BLOCKSIZE);
	shn_finish(&ctx, macbuf, MACSIZE);
	i += BLOCKSIZE;
    }
    t = clock() - t;
    printf("%f Mbyte per second MAC and encrypt %d-byte blocks %d-bit MAC\n",
	(((double)i/((double)t / (double)CLOCKS_PER_SEC))) / 1000000.0,
	BLOCKSIZE, MACSIZE*8);

    /* test combined decryption speed */
    t = clock();
    for (i = 0; i < 200000000; ) {
	shn_nonce(&ctx, testframe, 4);
	shn_decrypt(&ctx, bigbuf, BLOCKSIZE);
	shn_finish(&ctx, macbuf, MACSIZE);
	i += BLOCKSIZE;
    }
    t = clock() - t;
    printf("%f Mbyte per second decrypt and MAC %d-byte blocks %d-bit MAC\n",
	(((double)i/((double)t / (double)CLOCKS_PER_SEC))) / 1000000.0,
	BLOCKSIZE, MACSIZE*8);

    /* test key setup time */
    t = clock();
    for (i = 0; i < 10000000; ++i) {
	k[3] = i;
	shn_key(&ctx, (UCHAR *)k, 16);
    }
    t = clock() - t;
    printf("%f million 128-bit keys per second\n",
	(((double)i/((double)t / (double)CLOCKS_PER_SEC))) / 1000000.0);

    /* test nonce setup time */
    t = clock();
    for (i = 0; i < 10000000; ++i) {
	k[3] = i;
	shn_nonce(&ctx, (UCHAR *)k, 16);
    }
    t = clock() - t;
    printf("%f million 128-bit nonces per second\n",
	(((double)i/((double)t / (double)CLOCKS_PER_SEC))) / 1000000.0);
}

int
main(int ac, char **av)
{
    int         n, i;
    int		vflag = 0;
    UCHAR	key[32], nonce[32];
    int         keysz, noncesz;

    if (ac >= 2 && strcmp(av[1], "-verbose") == 0) {
	vflag = 1;
	v = vflag;
	++av, --ac;
    }
    if (ac == 2 && strcmp(av[1], "-test") == 0) {
        test_shn(0);
        return nerrors;
    }
    if (ac == 2 && strcmp(av[1], "-time") == 0) {
        time_shn();
        return 0;
    }
    if (ac == 2 && strcmp(av[1], "-bulk") == 0) {
	bulkflag = 1;
	--ac, ++av;
    }

    if (ac >= 2)
        hexread(key, av[1], keysz = strlen(av[1]) / 2);
    else
        hexread(key, "0000000000000000", keysz = 8);
    if (ac >= 3)
        hexread(nonce, av[2], noncesz = strlen(av[2]) / 2);
    else
        noncesz = 0;
    if (ac >= 4)
	sscanf(av[3], "%d", &n);
    else if (bulkflag)
	n = 1000000000L/8; /* 10^9 bits for NIST suite */
    else
	n = 1000000;

    shn_key(&ctx, key, keysz);
    shn_nonce(&ctx, nonce, noncesz);
    if (vflag) {
	printLFSR("Initial LFSR", ctx.initR);
    }
    while (n > 0) {
	i = sizeof bigbuf;
	i = n > i ? i : n;
	shn_stream(&ctx, bigbuf, i);
	if (bulkflag)
	    fwrite(bigbuf, i, 1, stdout);
	else
	    hexbulk(bigbuf, i);
	n -= i;
    }
    return 0;
}
