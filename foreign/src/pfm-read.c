/* PSPP - computes sample statistics.
   Copyright (C) 1997-9, 2000 Free Software Foundation, Inc.
   Written by Ben Pfaff <blp@gnu.org>.
   Modified for R foreign library by Saikat DebRoy <saikat@stat.wisc.edu>.

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of the
   License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA
   02111-1307, USA. */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <errno.h>
#include <math.h>
#include "foreign.h"
#include "avl.h"
#include "file-handle.h"
#include "format.h"
#include "pfm.h"
#include "var.h"

/* Clamps A to be between B and C. */
#define range(A, B, C)				\
	((A) < (B) ? (B) : ((A) > (C) ? (C) : (A)))

/* Divides nonnegative X by positive Y, rounding up. */
#define DIV_RND_UP(X, Y) 			\
	(((X) + ((Y) - 1)) / (Y))

/* Returns nonnegative difference between {nonnegative X} and {the
   least multiple of positive Y greater than or equal to X}. */
#if __GNUC__ && !__STRICT_ANSI__
#define REM_RND_UP(X, Y)			\
	({					\
	  int rem = (X) % (Y);			\
	  rem ? (Y) - rem : 0;			\
	})
#else
#define REM_RND_UP(X, Y) 			\
	((X) % (Y) ? (Y) - (X) % (Y) : 0)
#endif

/* Rounds X up to the next multiple of Y. */
#define ROUND_UP(X, Y) 				\
	(((X) + ((Y) - 1)) / (Y) * (Y))

/* Rounds X down to the previous multiple of Y. */
#define ROUND_DOWN(X, Y) 			\
	((X) / (Y) * (Y))

#undef DEBUGGING
/*#define DEBUGGING 1*/

static double 
second_lowest_double_val()
{
  /* PORTME: Set the value for second_lowest_value, which is the
     "second lowest" possible value for a double.  This is the value
     for LOWEST on MISSING VALUES, etc. */
#if FPREP == FPREP_IEEE754
#ifdef WORDS_BIGENDIAN
    union {
	unsigned char c[8];
	double d;
    } second_lowest = {{0xff, 0xef, 0xff, 0xff, 0xff, 0xff, 0xff, 0xfe}};
#else
    union {
	unsigned char c[8];
	double d;
    } second_lowest = {{0xfe, 0xff, 0xff, 0xff, 0xff, 0xff, 0xef, 0xff}};
#endif
    return second_lowest.d;
#else /* FPREP != FPREP_IEEE754 */
#error Unknown floating-point representation.
#endif /* FPREP != FPREP_IEEE754 */
}

#define SECOND_LOWEST_VALUE second_lowest_double_val()
#define NOT_INT INT_MIN

/* pfm's file_handle extension. */
struct pfm_fhuser_ext
  {
    FILE *file;			/* Actual file. */

    struct dictionary *dict;	/* File's dictionary. */
    int weight_index;		/* 0-based index of weight variable, or -1. */

    unsigned char *trans;	/* 256-byte character set translation table. */

    int nvars;			/* Number of variables. */
    int *vars;			/* Variable widths, 0 for numeric. */
    int case_size;		/* Number of `value's per case. */

    unsigned char buf[83];	/* Input buffer. */
    unsigned char *bp;		/* Buffer pointer. */
    int cc;			/* Current character. */
  };

static struct fh_ext_class pfm_r_class;

extern char *xstrdup(const char *s);

/* Closes a portable file after we're done with it. */
static void
pfm_close (struct file_handle * h)
{
  struct pfm_fhuser_ext *ext = h->ext;

  Free (ext->vars);
  Free (ext->trans);
  if (EOF == fclose (ext->file))
    error("%s: Closing portable file: %s.", h->fn, strerror (errno));
}

/* Displays the message X with corrupt_msg, then jumps to the lossage
   label. */
#define lose(X)					\
	do					\
	  {					\
	    warning X;				\
	    goto lossage;			\
	  }					\
	while (0)

/* Read an 80-character line into handle H's buffer.  Return
   success. */
static int
fill_buf (struct file_handle *h)
{
  struct pfm_fhuser_ext *ext = h->ext;

  if (80 != fread (ext->buf, 1, 80, ext->file))
    lose (("Unexpected end of file."));

  /* PORTME: line ends. */
  {
    int c;
    
    c = getc (ext->file);
    if (c != '\n' && c != '\r')
      lose (("Bad line end."));

    c = getc (ext->file);
    if (c != '\n' && c != '\r')
      ungetc (c, ext->file);
  }
  
  if (ext->trans)
    {
      int i;
      
      for (i = 0; i < 80; i++)
	ext->buf[i] = ext->trans[ext->buf[i]];
    }

  ext->bp = ext->buf;

  return 1;

 lossage:
  return 0;
}

/* Read a single character into cur_char.  Return success; */
static int
read_char (struct file_handle *h)
{
  struct pfm_fhuser_ext *ext = h->ext;

  if (ext->bp >= &ext->buf[80] && !fill_buf (h))
    return 0;
  ext->cc = *ext->bp++;
  return 1;
}

/* Advance a single character. */
#define advance() if (!read_char (h)) goto lossage

/* Skip a single character if present, and return whether it was
   skipped. */
static inline int
skip_char (struct file_handle *h, int c)
{
  struct pfm_fhuser_ext *ext = h->ext;
  
  if (ext->cc == c)
    {
      advance ();
      return 1;
    }
 lossage:
  return 0;
}

/* Skip a single character if present, and return whether it was
   skipped. */
#define match(C) skip_char (h, C)

static int read_header (struct file_handle *h);
static int read_version_data (struct file_handle *h, struct pfm_read_info *inf);
static int read_variables (struct file_handle *h);
static int read_value_label (struct file_handle *h);
void dump_dictionary (struct dictionary *dict);

/* Reads the dictionary from file with handle H, and returns it in a
   dictionary structure.  This dictionary may be modified in order to
   rename, reorder, and delete variables, etc. */
struct dictionary *
pfm_read_dictionary (struct file_handle *h, struct pfm_read_info *inf)
{
  /* The file handle extension record. */
  struct pfm_fhuser_ext *ext;

  /* Check whether the file is already open. */
  if (h->class == &pfm_r_class)
    {
      ext = h->ext;
      return ext->dict;
    }
  else if (h->class != NULL)
    {
      error("Cannot read file %s as portable file: already opened "
		 "for %s.",
	   fh_handle_name (h), h->class->name);
      return NULL;
    }

#if 0
  msg (VM (1), ("%s: Opening portable-file handle %s for reading."),
       fh_handle_filename (h), fh_handle_name (h));
#endif

  /* Open the physical disk file. */
  ext = (struct pfm_fhuser_ext *) Calloc(1, struct pfm_fhuser_ext);
  ext->file = fopen (R_ExpandFileName(h->norm_fn), "rb");
  if (ext->file == NULL)
    {
      Free (ext);
      error("An error occurred while opening \"%s\" for reading "
	   "as a portable file: %s.", h->fn, strerror (errno));
      return NULL;
    }

  /* Initialize the sfm_fhuser_ext structure. */
  h->class = &pfm_r_class;
  h->ext = ext;
  ext->dict = NULL;
  ext->trans = NULL;
  if (!fill_buf (h))
    goto lossage;
  advance ();

  /* Read the header. */
  if (!read_header (h))
    goto lossage;
  
  /* Read version, date info, product identification. */
  if (!read_version_data (h, inf))
    goto lossage;

  /* Read variables. */
  if (!read_variables (h))
    goto lossage;

  /* Value labels. */
  while (match (77 /* D */))
    if (!read_value_label (h))
      goto lossage;

  if (!match (79 /* F */))
    lose (("Data record expected."));

#if 0
  msg (VM (2), ("Read portable-file dictionary successfully."));
#endif

#if DEBUGGING
  dump_dictionary (ext->dict);
#endif
  return ext->dict;

 lossage:
  /* Come here on unsuccessful completion. */
  
  fclose (ext->file);
  if (ext && ext->dict)
    free_dictionary (ext->dict);
  Free (ext);
  h->class = NULL;
  h->ext = NULL;
  error("Error reading portable-file dictionary.");
  return NULL;
}

/* Read a floating point value and return its value, or
   second_lowest_value on error. */
static double
read_float (struct file_handle *h)
{
  struct pfm_fhuser_ext *ext = h->ext;			      
  double num = 0.;
  int got_dot = 0;
  int got_digit = 0;
  int exponent = 0;
  int neg = 0;

  /* Skip leading spaces. */
  while (match (126 /* space */))
    ;

  if (match (137 /* * */))
    {
      advance ();	/* Probably a dot (.) but doesn't appear to matter. */
      return NA_REAL;
    }
  else if (match (141 /* - */))
    neg = 1;

  for (;;)
    {
      if (ext->cc >= 64 /* 0 */ && ext->cc <= 93 /* T */)
	{
	  got_digit++;

	  /* Make sure that multiplication by 30 will not overflow.  */
	  if (num > DBL_MAX * (1. / 30.))
	    /* The value of the digit doesn't matter, since we have already
	       gotten as many digits as can be represented in a `double'.
	       This doesn't necessarily mean the result will overflow.
	       The exponent may reduce it to within range.

	       We just need to record that there was another
	       digit so that we can multiply by 10 later.  */
	    ++exponent;
	  else
	    num = (num * 30.0) + (ext->cc - 64);

	  /* Keep track of the number of digits after the decimal point.
	     If we just divided by 30 here, we would lose precision.  */
	  if (got_dot)
	    --exponent;
	}
      else if (!got_dot && ext->cc == 127 /* . */)
	/* Record that we have found the decimal point.  */
	got_dot = 1;
      else
	/* Any other character terminates the number.  */
	break;

      advance ();
    }

  if (!got_digit)
    lose (("Number expected."));
      
  if (ext->cc == 130 /* + */ || ext->cc == 141 /* - */)
    {
      /* Get the exponent.  */
      long int exp = 0;
      int neg_exp = ext->cc == 141 /* - */;

      for (;;)
	{
	  advance ();

	  if (ext->cc < 64 /* 0 */ || ext->cc > 93 /* T */)
	    break;

	  if (exp > LONG_MAX / 30)
	    goto overflow;
	  exp = exp * 30 + (ext->cc - 64);
	}

      /* We don't check whether there were actually any digits, but we
         probably should. */
      if (neg_exp)
	exp = -exp;
      exponent += exp;
    }
  
  if (!match (142 /* / */))
    lose (("Missing numeric terminator."));

  /* Multiply NUM by 30 to the EXPONENT power, checking for overflow.  */

  if (exponent < 0)
    num *= pow (30.0, (double) exponent);
  else if (exponent > 0)
    {
      if (num > DBL_MAX * pow (30.0, (double) -exponent))
	goto overflow;
      num *= pow (30.0, (double) exponent);
    }

  if (neg)
    return -num;
  else
    return num;

 overflow:
  if (neg)
    return -DBL_MAX / 10.;
  else
    return DBL_MAX / 10;

 lossage:
  return -DBL_MAX;
}
  
/* Read an integer and return its value, or NOT_INT on failure. */
int
read_int (struct file_handle *h)
{
  double f = read_float (h);

  if (f == SECOND_LOWEST_VALUE)
    goto lossage;
  if (floor (f) != f || f >= INT_MAX || f <= INT_MIN)
    lose (("Bad integer format."));
  return f;

 lossage:
  return NOT_INT;
}

/* Reads a string and returns its value in a static buffer, or NULL on
   failure.  The buffer can be deallocated by calling with a NULL
   argument. */
static unsigned char *
read_string (struct file_handle *h)
{
  struct pfm_fhuser_ext *ext = h->ext;
  static char *buf;
  int n;
  
  if (h == NULL)
    {
      Free (buf);
      buf = NULL;
      return NULL;
    }
  else if (buf == NULL)
    buf = Calloc (256, char);

  n = read_int (h);
  if (n == NOT_INT)
    return NULL;
  if (n < 0 || n > 255)
    lose (("Bad string length %d.", n));
  
  {
    int i;

    for (i = 0; i < n; i++)
      {
	buf[i] = ext->cc;
	advance ();
      }
  }
  
  buf[n] = 0;
  return buf;

 lossage:
  return NULL;
}

/* Reads the 464-byte file header. */
static int
read_header (struct file_handle *h)
{
  struct pfm_fhuser_ext *ext = h->ext;

  /* For now at least, just ignore the vanity splash strings. */
  {
    int i;

    for (i = 0; i < 200; i++)
      advance ();
  }
  
  {
    unsigned char src[256];
    int trans_temp[256];
    int i;

    for (i = 0; i < 256; i++)
      {
	src[i] = (unsigned char) ext->cc;
	advance ();
      }

    for (i = 0; i < 256; i++)
      trans_temp[i] = -1;

    /* 0 is used to mark untranslatable characters, so we have to mark
       it specially. */
    trans_temp[src[64]] = 64;
    for (i = 0; i < 256; i++)
      if (trans_temp[src[i]] == -1)
	trans_temp[src[i]] = i;
    
    ext->trans = Calloc (256, char);
    for (i = 0; i < 256; i++)
      ext->trans[i] = trans_temp[i] == -1 ? 0 : trans_temp[i];

    /* Translate the input buffer. */
    for (i = 0; i < 80; i++)
      ext->buf[i] = ext->trans[ext->buf[i]];
    ext->cc = ext->trans[ext->cc];
  }
  
  {
    unsigned char sig[8] = {92, 89, 92, 92, 89, 88, 91, 93};
    int i;

    for (i = 0; i < 8; i++)
      if (!match (sig[i]))
	lose (("Missing SPSSPORT signature."));
  }

  return 1;

 lossage:
  return 0;
}

/* Reads the version and date info record, as well as product and
   subproduct identification records if present. */
int
read_version_data (struct file_handle *h, struct pfm_read_info *inf)
{
  struct pfm_fhuser_ext *ext = h->ext;

  /* Version. */
  if (!match (74 /* A */))
    lose (("Unrecognized version code %d.", ext->cc));

  /* Date. */
  {
    static const int map[] = {6, 7, 8, 9, 3, 4, 0, 1};
    char *date = read_string (h);
    int i;
    
    if (!date)
      return 0;
    if (strlen (date) != 8)
      lose (("Bad date string length %d.", strlen (date)));
    if (date[0] == ' ') /* the first field of date can be ' ' in some
			   windows versions of SPSS */
	date[0] = '0';
    for (i = 0; i < 8; i++)
      {
	if (date[i] < 64 /* 0 */ || date[i] > 73 /* 9 */)
	  lose (("Bad character in date."));
	if (inf)
	  inf->creation_date[map[i]] = date[i] - 64 /* 0 */ + '0';
      }
    if (inf)
      {
	inf->creation_date[2] = inf->creation_date[5] = ' ';
	inf->creation_date[10] = 0;
      }
  }
  
  /* Time. */
  {
    static const int map[] = {0, 1, 3, 4, 6, 7};
    char *time = read_string (h);
    int i;

    if (!time)
      return 0;
    if (strlen (time) != 6)
      lose (("Bad time string length %d.", strlen (time)));
    if (time[0] == ' ') /* the first field of date can be ' ' in some
			   windows versions of SPSS */
	time[0] = '0';
    for (i = 0; i < 6; i++)
      {
	if (time[i] < 64 /* 0 */ || time[i] > 73 /* 9 */)
	  lose (("Bad character in time."));
	if (inf)
	  inf->creation_time[map[i]] = time[i] - 64 /* 0 */ + '0';
      }
    if (inf)
      {
	inf->creation_time[2] = inf->creation_time[5] = ' ';
	inf->creation_time[8] = 0;
      }
  }

  /* Product. */
  if (match (65 /* 1 */))
    {
      char *product;
      
      product = read_string (h);
      if (product == NULL)
	return 0;
      if (inf)
	strncpy (inf->product, product, 61);
    }
  else if (inf)
    inf->product[0] = 0;

  /* Subproduct. */
  if (match (67 /* 3 */))
    {
      char *subproduct;

      subproduct = read_string (h);
      if (subproduct == NULL)
	return 0;
      if (inf)
	strncpy (inf->subproduct, subproduct, 61);
    }
  else if (inf)
    inf->subproduct[0] = 0;
  return 1;
  
 lossage:
  return 0;
}

static int
convert_format (struct file_handle *h, int fmt[3], struct fmt_spec *v,
		struct variable *vv)
{
  if (fmt[0] < 0
      || (size_t) fmt[0] >= sizeof translate_fmt / sizeof *translate_fmt)
    lose (("%s: Bad format specifier byte %d.", vv->name, fmt[0]));

  v->type = translate_fmt[fmt[0]];
  v->w = fmt[1];
  v->d = fmt[2];

  /* FIXME?  Should verify the resulting specifier more thoroughly. */

  if (v->type == -1)
    lose (("%s: Bad format specifier byte (%d).", vv->name, fmt[0]));
  if ((vv->type == ALPHA) ^ ((formats[v->type].cat & FCAT_STRING) != 0))
    lose (("%s variable %s has %s format specifier %s.",
	   vv->type == ALPHA ? "String" : "Numeric",
	   vv->name,
	   formats[v->type].cat & FCAT_STRING ? "string" : "numeric",
	   formats[v->type].name));
  return 1;

 lossage:
  return 0;
}

/* Translation table from SPSS character code to this computer's
   native character code (which is probably ASCII). */
static const unsigned char spss2ascii[256] =
  {
    "                                                                "
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz ."
    "<(+|&[]!$*);^-/|,%_>?`:$@'=\"      ~-   0123456789   -() {}\\     "
    "                                                                "
  };

/* Translate string S into ASCII. */
static void
asciify (char *s)
{
  for (; *s; s++)
    *s = spss2ascii[(unsigned char) *s];
}

static int parse_value (struct file_handle *, union value *, struct variable *);

/* Read information on all the variables.  */
static int
read_variables (struct file_handle *h)
{
  struct pfm_fhuser_ext *ext = h->ext;
  int i;
  
  if (!match (68 /* 4 */))
    lose (("Expected variable count record."));
  
  ext->nvars = read_int (h);
  if (ext->nvars <= 0 || ext->nvars == NOT_INT)
    lose (("Invalid number of variables %d.", ext->nvars));
  ext->vars = Calloc (ext->nvars, int);

  /* Purpose of this value is unknown.  It is typically 161. */
  {
    int x = read_int (h);

    if (x == NOT_INT)
      goto lossage;

/*  According to Akio Sone, there are cases where this is 160 */
/*      if (x != 161) */
/*        warning("Unexpected flag value %d.", x); */
  }

  ext->dict = new_dictionary (0);

  if (match (70 /* 6 */))
    {
      char *name = read_string (h);
      if (!name)
	goto lossage;

      strcpy (ext->dict->weight_var, name);
      asciify (ext->dict->weight_var);
    }
  
  for (i = 0; i < ext->nvars; i++)
    {
      int width;
      unsigned char *name;
      int fmt[6];
      struct variable *v;
      int j;

      if (!match (71 /* 7 */))
	lose (("Expected variable record."));

      width = read_int (h);
      if (width == NOT_INT)
	goto lossage;
      if (width < 0)
	lose (("Invalid variable width %d.", width));
      ext->vars[i] = width;
      
      name = read_string (h);
      if (name == NULL)
	goto lossage;
      for (j = 0; j < 6; j++)
	{
	  fmt[j] = read_int (h);
	  if (fmt[j] == NOT_INT)
	    goto lossage;
	}

      /* Verify first character of variable name.

	 Weirdly enough, there is no # character in the SPSS portable
	 character set, so we can't check for it. */
      if (strlen (name) > 8)
	lose (("position %d: Variable name has %u characters.",
	       i, strlen (name)));
      if ((name[0] < 74 /* A */ || name[0] > 125 /* Z */)
	  && name[0] != 152 /* @ */)
	lose (("position %d: Variable name begins with invalid "
	       "character.", i));
      if (name[0] >= 100 /* a */ && name[0] <= 125 /* z */)
	{
	  warning("position %d: Variable name begins with "
		  "lowercase letter %c.",
		  i, name[0] - 100 + 'a');
	  name[0] -= 26 /* a - A */;
	}

      /* Verify remaining characters of variable name. */
      for (j = 1; j < (int) strlen (name); j++)
	{
	  int c = name[j];

	  if (c >= 100 /* a */ && c <= 125 /* z */)
	    {
	      warning("position %d: Variable name character %d "
		      "is lowercase letter %c.",
		      i, j + 1, c - 100 + 'a');
	      name[j] -= 26 /* z - Z */;
	    }
	  else if ((c >= 64 /* 0 */ && c <= 99 /* Z */)
		   || c == 127 /* . */ || c == 152 /* @ */
		   || c == 136 /* $ */ || c == 146 /* _ */)
	    name[j] = c;
	  else
	    lose (("position %d: character `\\%03o' is not "
			"valid in a variable name.", i, c));
	}

      asciify (name);
      if (width < 0 || width > 255)
	lose (("Bad width %d for variable %s.", width, name));

      v = create_variable (ext->dict, name, width ? ALPHA : NUMERIC, width);
      v->get.fv = v->fv;
      if (v == NULL)
	lose (("Duplicate variable name %s.", name));
      if (!convert_format (h, &fmt[0], &v->print, v))
	goto lossage;
      if (!convert_format (h, &fmt[3], &v->write, v))
	goto lossage;

      /* Range missing values. */
      if (match (75 /* B */))
	{
	  v->miss_type = MISSING_RANGE;
	  if (!parse_value (h, &v->missing[0], v)
	      || !parse_value (h, &v->missing[1], v))
	    goto lossage;
	}
      else if (match (74 /* A */))
	{
	  v->miss_type = MISSING_HIGH;
	  if (!parse_value (h, &v->missing[0], v))
	    goto lossage;
	}
      else if (match (73 /* 9 */))
	{
	  v->miss_type = MISSING_LOW;
	  if (!parse_value (h, &v->missing[0], v))
	    goto lossage;
	}

      /* Single missing values. */
      while (match (72 /* 8 */))
	{
	  static const int map_next[MISSING_COUNT] =
	    {
	      MISSING_1, MISSING_2, MISSING_3, -1,
	      MISSING_RANGE_1, MISSING_LOW_1, MISSING_HIGH_1,
	      -1, -1, -1,
	    };

	  static const int map_ofs[MISSING_COUNT] = 
	    {
	      -1, 0, 1, 2, -1, -1, -1, 2, 1, 1,
	    };

	  v->miss_type = map_next[v->miss_type];
	  if (v->miss_type == -1)
	    lose (("Bad missing values for %s.", v->name));
	  
	  if (map_ofs[v->miss_type] == -1)
	      error("read_variables : map_ofs[v->miss_type] == -1");
	  if (!parse_value (h, &v->missing[map_ofs[v->miss_type]], v))
	    goto lossage;
	}

      if (match (76 /* C */))
	{
	  char *label = read_string (h);
	  
	  if (label == NULL)
	    goto lossage;

	  v->label = xstrdup (label);
	  asciify (v->label);
	}
    }
  ext->case_size = ext->dict->nval;

  if (ext->dict->weight_var[0] != 0
      && !find_dict_variable (ext->dict, ext->dict->weight_var))
    lose (("Weighting variable %s not present in dictionary.",
	   ext->dict->weight_var));

  return 1;

 lossage:
  return 0;
}

/* Parse a value for variable VV into value V.  Returns success. */
static int
parse_value (struct file_handle *h, union value *v, struct variable *vv)
{
  if (vv->type == ALPHA)
    {
      char *mv = read_string (h);
      int j;
      
      if (mv == NULL)
	return 0;

      strncpy (v->s, mv, 8);
      for (j = 0; j < 8; j++)
	if (v->s[j])
	  v->s[j] = spss2ascii[v->s[j]];
	else
	  /* Value labels are always padded with spaces. */
	  v->s[j] = ' ';
    }
  else
    {
      v->f = read_float (h);
      if (v->f == SECOND_LOWEST_VALUE)
	return 0;
    }

  return 1;
}

/* Parse a value label record and return success. */
static int
read_value_label (struct file_handle *h)
{
  struct pfm_fhuser_ext *ext = h->ext;

  /* Variables. */
  int nv;
  struct variable **v;

  /* Labels. */
  int n_labels;

  int i;

  nv = read_int (h);
  if (nv == NOT_INT)
    return 0;

  v = Calloc (nv, struct variable *);
  for (i = 0; i < nv; i++)
    {
      char *name = read_string (h);
      if (name == NULL)
	goto lossage;
      asciify (name);

      v[i] = find_dict_variable (ext->dict, name);
      if (v[i] == NULL)
	lose (("Unknown variable %s while parsing value labels.", name));

      if (v[0]->width != v[i]->width)
	lose (("Cannot assign value labels to %s and %s, which "
		    "have different variable types or widths.",
	       v[0]->name, v[i]->name));
    }

  n_labels = read_int (h);
  if (n_labels == NOT_INT)
    goto lossage;

  for (i = 0; i < n_labels; i++)
    {
      union value val;
      char *label;
      struct value_label *vl;

      int j;
      
      if (!parse_value (h, &val, v[0]))
	goto lossage;
      
      label = read_string (h);
      if (label == NULL)
	goto lossage;
      asciify (label);

      /* Create a label. */
      vl = Calloc (1, struct value_label);
      vl->v = val;
      vl->s = xstrdup (label);
      vl->ref_count = nv;

      /* Assign the value_label's to each variable. */
      for (j = 0; j < nv; j++)
	{
	  struct variable *var = v[j];
	  struct value_label *old;

	  /* Create AVL tree if necessary. */
	  if (!var->val_lab)
	    var->val_lab = avl_create (val_lab_cmp,
				       (void *) (var->width));

	  old = avl_replace (var->val_lab, vl);
	  if (old == NULL)
	    continue;

	  if (var->type == NUMERIC)
	    lose (("Duplicate label for value %g for variable %s.",
		   vl->v.f, var->name));
	  else
	    lose (("Duplicate label for value `%.*s' for variable %s.",
		   var->width, vl->v.s, var->name));

	  free_value_label (old);
	}
    }
  Free (v);
  return 1;

 lossage:
  Free (v);
  return 0;
}

/* Copies SRC to DEST, truncating to N characters or right-padding
   with spaces to N characters as necessary.  Does not append a null
   character.  SRC must be null-terminated. */
static void
st_bare_pad_copy (char *dest, const char *src, size_t n)
{
  size_t len = strlen (src);
  if (len >= n)
    memcpy (dest, src, n);
  else
    {
      memcpy (dest, src, len);
      memset (&dest[len], ' ', n - len);
    }
}

/* Reads one case from portable file H into the value array PERM
   according to the instuctions given in associated dictionary DICT,
   which must have the get.fv elements appropriately set.  Returns
   nonzero only if successful. */
int
pfm_read_case (struct file_handle *h, union value *perm, struct dictionary *dict)
{
  struct pfm_fhuser_ext *ext = h->ext;

  union value *temp, *tp;
  int i;

  /* Check for end of file. */
  if (ext->cc == 99 /* Z */)
    return 0;
  
  /* The first concern is to obtain a full case relative to the data
     file.  (Cases in the data file have no particular relationship to
     cases in the active file.) */
  tp = temp = Calloc (ext->case_size, union value);
  for (tp = temp, i = 0; i < ext->nvars; i++)
    if (ext->vars[i] == 0)
      {
	tp->f = read_float (h);
	if (tp->f == SECOND_LOWEST_VALUE)
	  goto unexpected_eof;
	tp++;
      }
    else
      {
	char *s = read_string (h);
	if (s == NULL)
	  goto unexpected_eof;
	asciify (s);
	  
	st_bare_pad_copy (tp->s, s, ext->vars[i]);
	tp += DIV_RND_UP (ext->vars[i], MAX_SHORT_STRING);
      }

  /* Translate a case in data file format to a case in active file
     format. */
  for (i = 0; i < dict->nvar; i++)
    {
      struct variable *v = dict->var[i];

      if (v->get.fv == -1)
	continue;
      
      if (v->type == NUMERIC)
	perm[v->fv].f = temp[v->get.fv].f;
      else
	memcpy (perm[v->fv].c, &temp[v->get.fv], v->width);
    }

  Free (temp);
  return 1;

 unexpected_eof:
  lose (("End of file midway through case."));

 lossage:
  Free (temp);
  return 0;
}

static struct fh_ext_class pfm_r_class =
{
  5,
  "reading as a portable file",
  pfm_close,
};
