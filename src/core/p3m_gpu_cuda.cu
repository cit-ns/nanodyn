/* 
   Copyright (C) 2010,2011,2012,2013,2014 The ESPResSo project

   This file is part of ESPResSo.
  
   ESPResSo is free software: you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.
   
   ESPResSo is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   
   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

/** \file p3m_gpu_cuda.cu
 *
 * Cuda (.cu) file for the P3M electrostatics method.
 * Header file \ref p3m_gpu.hpp .
 */ 

#include "config.hpp"

#ifdef ELECTROSTATICS

#ifdef P3M_GPU_DEBUG
#define P3M_GPU_TRACE(A) A
#else
#define P3M_GPU_TRACE(A)
#endif

#include <stdio.h>
#include <stdlib.h>

#include <cuda.h>
#include <cufft.h>
#include "cuda_interface.hpp"
#include "cuda_utils.hpp"

#include "p3m_gpu.hpp"
#include "utils.hpp"
#include "EspressoSystemInterface.hpp"
#include "interaction_data.hpp"

struct dummytypename {
  CUFFT_TYPE_COMPLEX *charge_mesh;
  CUFFT_TYPE_COMPLEX *force_mesh_x;
  CUFFT_TYPE_COMPLEX *force_mesh_y;
  CUFFT_TYPE_COMPLEX *force_mesh_z;
  REAL_TYPE *G_hat;
  cufftHandle fft_plan;
  int cao, mesh;
  REAL_TYPE alpha;
  int npart;
  REAL_TYPE box;
} p3m_gpu_data;

static char p3m_gpu_data_initialized = 0;

#define SQR(A) ((A)*(A))

extern __shared__ float weights[];

__host__ __device__ inline double csinc(double d)
{
#define epsi 0.1

#define c2 -0.1666666666667e-0
#define c4  0.8333333333333e-2
#define c6 -0.1984126984127e-3
#define c8  0.2755731922399e-5

  double PId = PI*d, PId2;

  if (fabs(d)>epsi)
    return sin(PId)/PId;
  else {
    PId2 = SQR(PId);
    return 1.0 + PId2*(c2+PId2*(c4+PId2*(c6+PId2*c8)));
  }
}

/* @TODO: switch to bigger spline function. Needs adjustment of the tuning to be useful. */
// template<int cao_value>
// __device__ REAL_TYPE caf(const int i, const REAL_TYPE y) {
//   const REAL_TYPE x = -y;
//   switch(cao_value){
//   case 1: switch(i) {
//     case 0 : return 1;
//     default: return 0.0;
//     }
//   case 2: switch(i) {
//     case 0 : return 0.5 + x;
//     case 1 : return 0.5 - x;
//     default: return 0.0;
//     }
//   case 3: switch(i) {
//     case 0 : return SQR(1 + 2*x)/8.;
//     case 1 : return 0.75 - SQR(x);
//     case 2 : return SQR(1 - 2*x)/8.;
//     default: return 0.0;
//     }
//   case 4: switch(i) {
//     case 0 : return (1 + x*(6 + x*(12 + 8*x)))/48.;
//     case 1 : return (23 + x*(30 + (-12 - 24*x)*x))/48.;
//     case 2 : return (23 + x*(-30 + x*(-12 + 24*x)))/48.;
//     case 3 : return (1 + x*(-6 + (12 - 8*x)*x))/48.;
//     default: return 0.0;
//     }
//   case 5: switch(i) {
//     case 0 : return (1 + x*(8 + x*(24 + x*(32 + 16*x))))/384.;
//     case 1 : return (19 + x*(44 + x*(24 + (-16 - 16*x)*x)))/96.;
//     case 2 : return (115 + x*x*(-120 + 48*x*x))/192.;
//     case 3 : return (19 + x*(-44 + x*(24 + (16 - 16*x)*x)))/96.;
//     case 4 : return (1 + x*(-8 + x*(24 + x*(-32 + 16*x))))/384.;
//     default: return 0.0;
//     }
//   case 6: switch(i) {
//     case 0 : return (1 + x*(10 + x*(40 + x*(80 + x*(80 + 32*x)))))/3840.;
//     case 1 : return (237 + x*(750 + x*(840 + x*(240 + (-240 - 160*x)*x))))/3840.;
//     case 2 : return (841 + x*(770 + x*(-440 + x*(-560 + x*(80 + 160*x)))))/1920.;
//     case 3 : return (841 + x*(-770 + x*(-440 + x*(560 + (80 - 160*x)*x))))/1920.;
//     case 4 : return (237 + x*(-750 + x*(840 + x*(-240 + x*(-240 + 160*x)))))/3840.;
//     case 5 : return (1 + x*(-10 + x*(40 + x*(-80 + (80 - 32*x)*x))))/3840.;
//     default: return 0.0;
//     }
//   case 7: switch(i) {
//     case 0 : return (1 + x*(12 + x*(60 + x*(160 + x*(240 + x*(192 + 64*x))))))/46080.;
//     case 1 : return (361 + x*(1416 + x*(2220 + x*(1600 + x*(240 + (-384 - 192*x)*x)))))/23040.;
//     case 2 : return (10543 + x*(17340 + x*(4740 + x*(-6880 + x*(-4080 + x*(960 + 960*x))))))/46080.;
//     case 3 : return (5887 + x*x*(-4620 + x*x*(1680 - 320*x*x)))/11520.;
//     case 4 : return (10543 + x*(-17340 + x*(4740 + x*(6880 + x*(-4080 + x*(-960 + 960*x))))))/46080.;
//     case 5 : return (361 + x*(-1416 + x*(2220 + x*(-1600 + x*(240 + (384 - 192*x)*x)))))/23040.;
//     case 6 : return (1 + x*(-12 + x*(60 + x*(-160 + x*(240 + x*(-192 + 64*x))))))/46080.;
//     default: return 0.0;
//     }
//   case 8: switch(i) {
//     case 0 : return (1 + x*(14 + x*(84 + x*(280 + x*(560 + x*(672 + x*(448 + 128*x)))))))/645120.;
//     case 1 : return (2179 + x*(10094 + x*(19740 + x*(20440 + x*(10640 + x*(672 + (-2240 - 896*x)*x))))))/645120.;
//     case 2 : return (60657 + x*(137494 + x*(101556 + x*(1400 + x*(-35280 + x*(-12768 + x*(4032 + 2688*x)))))))/645120.;
//     case 3 : return (259723 + x*(182070 + x*(-121380 + x*(-108360 + x*(24080 + x*(30240 + (-2240 - 4480*x)*x))))))/645120.;
//     case 4 : return (259723 + x*(-182070 + x*(-121380 + x*(108360 + x*(24080 + x*(-30240 + x*(-2240 + 4480*x)))))))/645120.;
//     case 5 : return (60657 + x*(-137494 + x*(101556 + x*(-1400 + x*(-35280 + x*(12768 + (4032 - 2688*x)*x))))))/645120.;
//     case 6 : return (2179 + x*(-10094 + x*(19740 + x*(-20440 + x*(10640 + x*(-672 + x*(-2240 + 896*x)))))))/645120.;
//     case 7 : return (1 + x*(-14 + x*(84 + x*(-280 + x*(560 + x*(-672 + (448 - 128*x)*x))))))/645120.;
//     default: return 0.0;
//     }
//   case 9: switch(i) {
//     case 0 : return (1 + x*(16 + x*(112 + x*(448 + x*(1120 + x*(1792 + x*(1792 + x*(1024 + 256*x))))))))/1.032192e7;
//     case 1 : return (819 + x*(4356 + x*(10080 + x*(13104 + x*(10080 + x*(4032 + (-768 - 256*x)*x*x))))))/1.29024e6;
//     case 2 : return (82903 + x*(233912 + x*(254800 + x*(109088 + x*(-19040 + x*(-36736 + x*(-8960 + x*(3584 + 1792*x))))))))/2.58048e6;
//     case 3 : return (310661 + x*(398132 + x*(44576 + x*(-148624 + x*(-54880 + x*(23744 + x*(14336 + (-1792 - 1792*x)*x)))))))/1.29024e6;
//     case 4 : return (2337507 + x*x*(-1456560 + x*x*(433440 + x*x*(-80640 + 8960*x*x))))/5.16096e6;
//     case 5 : return (310661 + x*(-398132 + x*(44576 + x*(148624 + x*(-54880 + x*(-23744 + x*(14336 + (1792 - 1792*x)*x)))))))/1.29024e6;
//     case 6 : return (82903 + x*(-233912 + x*(254800 + x*(-109088 + x*(-19040 + x*(36736 + x*(-8960 + x*(-3584 + 1792*x))))))))/2.58048e6;
//     case 7 : return (819 + x*(-4356 + x*(10080 + x*(-13104 + x*(10080 + x*(-4032 + (768 - 256*x)*x*x))))))/1.29024e6;
//     case 8 : return (1 + x*(-16 + x*(112 + x*(-448 + x*(1120 + x*(-1792 + x*(1792 + x*(-1024 + 256*x))))))))/1.032192e7;
//     default: return 0.0;
//     }
//   case 10: switch(i) {
//     case 0 : return (1 + x*(18 + x*(144 + x*(672 + x*(2016 + x*(4032 + x*(5376 + x*(4608 + x*(2304 + 512*x)))))))))/1.8579456e8;
//     case 1 : return (19673 + x*(117918 + x*(313488 + x*(483168 + x*(469728 + x*(286272 + x*(91392 + x*(-4608 + (-16128 - 4608*x)*x))))))))/1.8579456e8;
//     case 2 : return (439085 + x*(1462770 + x*(2026800 + x*(1407840 + x*(372960 + x*(-141120 + x*(-134400 + x*(-23040 + x*(11520 + 4608*x)))))))))/4.644864e7;
//     case 3 : return (5426993 + x*(9691542 + x*(5061168 + x*(-993888 + x*(-1828512 + x*(-326592 + x*(252672 + x*(96768 + (-16128 - 10752*x)*x))))))))/4.644864e7;
//     case 4 : return (34706647 + x*(19707534 + x*(-14332752 + x*(-9809184 + x*(2675232 + x*(2350656 + x*(-284928 + x*(-354816 + x*(16128 + 32256*x)))))))))/9.289728e7;
//     case 5 : return (34706647 + x*(-19707534 + x*(-14332752 + x*(9809184 + x*(2675232 + x*(-2350656 + x*(-284928 + x*(354816 + (16128 - 32256*x)*x))))))))/9.289728e7;
//     case 6 : return (5426993 + x*(-9691542 + x*(5061168 + x*(993888 + x*(-1828512 + x*(326592 + x*(252672 + x*(-96768 + x*(-16128 + 10752*x)))))))))/4.644864e7;
//     case 7 : return (439085 + x*(-1462770 + x*(2026800 + x*(-1407840 + x*(372960 + x*(141120 + x*(-134400 + x*(23040 + (11520 - 4608*x)*x))))))))/4.644864e7;
//     case 8 : return (19673 + x*(-117918 + x*(313488 + x*(-483168 + x*(469728 + x*(-286272 + x*(91392 + x*(4608 + x*(-16128 + 4608*x)))))))))/1.8579456e8;
//     case 9 : return (1 + x*(-18 + x*(144 + x*(-672 + x*(2016 + x*(-4032 + x*(5376 + x*(-4608 + (2304 - 512*x)*x))))))))/1.8579456e8;
//     default: return 0.0;
//     }
//   case 11: switch(i) {
//     case 0 : return (1 + x*(20 + x*(180 + x*(960 + x*(3360 + x*(8064 + x*(13440 + x*(15360 + x*(11520 + x*(5120 + 1024*x))))))))))/3.7158912e9;
//     case 1 : return (29519 + x*(196720 + x*(589500 + x*(1044480 + x*(1206240 + x*(935424 + x*(470400 + x*(122880 + x*(-11520 + (-20480 - 5120*x)*x)))))))))/1.8579456e9;
//     case 2 : return (9116141 + x*(34733340 + x*(57331620 + x*(51958080 + x*(25740960 + x*(4088448 + x*(-2835840 + x*(-1797120 + x*(-218880 + x*(138240 + 46080*x))))))))))/3.7158912e9;
//     case 3 : return (22287613 + x*(49879080 + x*(41143860 + x*(10114560 + x*(-6004320 + x*(-4402944 + x*(-309120 + x*(552960 + x*(149760 + (-30720 - 15360*x)*x)))))))))/4.644864e8;
//     case 4 : return (453461641 + x*(477053220 + x*(3244500 + x*(-163033920 + x*(-39107040 + x*(25329024 + x*(10012800 + x*(-2257920 + x*(-1370880 + x*(107520 + 107520*x))))))))))/1.8579456e9;
//     case 5 : return (381773117 + x*x*(-197075340 + x*x*(49045920 + x*x*(-7835520 + x*x*(887040 - 64512*x*x)))))/9.289728e8;
//     case 6 : return (453461641 + x*(-477053220 + x*(3244500 + x*(163033920 + x*(-39107040 + x*(-25329024 + x*(10012800 + x*(2257920 + x*(-1370880 + x*(-107520 + 107520*x))))))))))/1.8579456e9;
//     case 7 : return (22287613 + x*(-49879080 + x*(41143860 + x*(-10114560 + x*(-6004320 + x*(4402944 + x*(-309120 + x*(-552960 + x*(149760 + (30720 - 15360*x)*x)))))))))/4.644864e8;
//     case 8 : return (9116141 + x*(-34733340 + x*(57331620 + x*(-51958080 + x*(25740960 + x*(-4088448 + x*(-2835840 + x*(1797120 + x*(-218880 + x*(-138240 + 46080*x))))))))))/3.7158912e9;
//     case 9 : return (29519 + x*(-196720 + x*(589500 + x*(-1044480 + x*(1206240 + x*(-935424 + x*(470400 + x*(-122880 + x*(-11520 + (20480 - 5120*x)*x)))))))))/1.8579456e9;
//     case 10 : return (1 + x*(-20 + x*(180 + x*(-960 + x*(3360 + x*(-8064 + x*(13440 + x*(-15360 + x*(11520 + x*(-5120 + 1024*x))))))))))/3.7158912e9;
//     default: return 0.0;
//     }
//   case 12: switch(i) {
//     case 0 : return (1 + x*(22 + x*(220 + x*(1320 + x*(5280 + x*(14784 + x*(29568 + x*(42240 + x*(42240 + x*(28160 + x*(11264 + 2048*x)))))))))))/8.17496064e10;
//     case 1 : return (177135 + x*(1298814 + x*(4327620 + x*(8644680 + x*(11484000 + x*(10600128 + x*(6830208 + x*(2914560 + x*(633600 + x*(-84480 + (-101376 - 22528*x)*x))))))))))/8.17496064e10;
//     case 2 : return (46702427 + x*(199256266 + x*(377738900 + x*(411785880 + x*(274280160 + x*(102645312 + x*(8131200 + x*(-11869440 + x*(-5617920 + x*(-478720 + x*(394240 + 112640*x)))))))))))/8.17496064e10;
//     case 3 : return (467693575 + x*(1240688262 + x*(1335764100 + x*(664447080 + x*(53090400 + x*(-108204096 + x*(-48048000 + x*(380160 + x*(5702400 + x*(1154560 + (-281600 - 112640*x)*x))))))))))/2.72498688e10;
//     case 4 : return (1806137183 + x*(2671615386 + x*(1017635300 + x*(-394364520 + x*(-373068960 + x*(-22131648 + x*(52483200 + x*(11784960 + x*(-4097280 + x*(-1605120 + x*(168960 + 112640*x)))))))))))/1.36249344e10;
//     case 5 : return (4764669969 + x*(2273953682 + x*(-1749195140 + x*(-971410440 + x*(298895520 + x*(201225024 + x*(-30957696 + x*(-26906880 + x*(2069760 + x*(2562560 + (-78848 - 157696*x)*x))))))))))/1.36249344e10;
//     case 6 : return (4764669969 + x*(-2273953682 + x*(-1749195140 + x*(971410440 + x*(298895520 + x*(-201225024 + x*(-30957696 + x*(26906880 + x*(2069760 + x*(-2562560 + x*(-78848 + 157696*x)))))))))))/1.36249344e10;
//     case 7 : return (1806137183 + x*(-2671615386 + x*(1017635300 + x*(394364520 + x*(-373068960 + x*(22131648 + x*(52483200 + x*(-11784960 + x*(-4097280 + x*(1605120 + (168960 - 112640*x)*x))))))))))/1.36249344e10;
//     case 8 : return (467693575 + x*(-1240688262 + x*(1335764100 + x*(-664447080 + x*(53090400 + x*(108204096 + x*(-48048000 + x*(-380160 + x*(5702400 + x*(-1154560 + x*(-281600 + 112640*x)))))))))))/2.72498688e10;
//     case 9 : return (46702427 + x*(-199256266 + x*(377738900 + x*(-411785880 + x*(274280160 + x*(-102645312 + x*(8131200 + x*(11869440 + x*(-5617920 + x*(478720 + (394240 - 112640*x)*x))))))))))/8.17496064e10;
//     case 10 : return (177135 + x*(-1298814 + x*(4327620 + x*(-8644680 + x*(11484000 + x*(-10600128 + x*(6830208 + x*(-2914560 + x*(633600 + x*(84480 + x*(-101376 + 22528*x)))))))))))/8.17496064e10;
//     case 11 : return (1 + x*(-22 + x*(220 + x*(-1320 + x*(5280 + x*(-14784 + x*(29568 + x*(-42240 + x*(42240 + x*(-28160 + (11264 - 2048*x)*x))))))))))/8.17496064e10;
//     default: return 0.0;
//     }
//   case 13: switch(i) {
//     case 0 : return (1 + x*(24 + x*(264 + x*(1760 + x*(7920 + x*(25344 + x*(59136 + x*(101376 + x*(126720 + x*(112640 + x*(67584 + x*(24576 + 4096*x))))))))))))/1.9619905536e12;
//     case 1 : return (132857 + x*(1062804 + x*(3896376 + x*(8654800 + x*(12965040 + x*(13774464 + x*(10585344 + x*(5829120 + x*(2154240 + x*(394240 + x*(-67584 + (-61440 - 12288*x)*x)))))))))))/4.904976384e11;
//     case 2 : return (118615985 + x*(558303504 + x*(1187744712 + x*(1493645120 + x*(1209423600 + x*(630710784 + x*(184090368 + x*(2230272 + x*(-22176000 + x*(-8335360 + x*(-473088 + x*(540672 + 135168*x))))))))))))/9.809952768e11;
//     case 3 : return (2677227797 + x*(8138269788 + x*(10568425560 + x*(7259106800 + x*(2372333040 + x*(-138010752 + x*(-427257600 + x*(-130521600 + x*(9757440 + x*(15150080 + x*(2365440 + (-675840 - 225280*x)*x)))))))))))/4.904976384e11;
//     case 4 : return (40461260069 + x*(75469938984 + x*(49230510120 + x*(5596052000 + x*(-8719056720 + x*(-3836295936 + x*(255763200 + x*(524620800 + x*(69569280 + x*(-37058560 + x*(-10475520 + x*(1351680 + 675840*x))))))))))))/6.539968512e11;
//     case 5 : return (19875856851 + x*(17751196716 + x*(-1192985112 + x*(-5533660880 + x*(-865568880 + x*(806357376 + x*(223356672 + x*(-71520768 + x*(-29018880 + x*(4111360 + x*(2500608 + (-135168 - 135168*x)*x)))))))))))/8.17496064e10;
//     case 6 : return (61940709597 + x*x*(-27287444184 + x*x*(5828462640 + x*x*(-804900096 + x*x*(80720640 + x*x*(-6150144 + 315392*x*x))))))/1.634992128e11;
//     case 7 : return (19875856851 + x*(-17751196716 + x*(-1192985112 + x*(5533660880 + x*(-865568880 + x*(-806357376 + x*(223356672 + x*(71520768 + x*(-29018880 + x*(-4111360 + x*(2500608 + (135168 - 135168*x)*x)))))))))))/8.17496064e10;
//     case 8 : return (40461260069 + x*(-75469938984 + x*(49230510120 + x*(-5596052000 + x*(-8719056720 + x*(3836295936 + x*(255763200 + x*(-524620800 + x*(69569280 + x*(37058560 + x*(-10475520 + x*(-1351680 + 675840*x))))))))))))/6.539968512e11;
//     case 9 : return (2677227797 + x*(-8138269788 + x*(10568425560 + x*(-7259106800 + x*(2372333040 + x*(138010752 + x*(-427257600 + x*(130521600 + x*(9757440 + x*(-15150080 + x*(2365440 + (675840 - 225280*x)*x)))))))))))/4.904976384e11;
//     case 10 : return (118615985 + x*(-558303504 + x*(1187744712 + x*(-1493645120 + x*(1209423600 + x*(-630710784 + x*(184090368 + x*(-2230272 + x*(-22176000 + x*(8335360 + x*(-473088 + x*(-540672 + 135168*x))))))))))))/9.809952768e11;
//     case 11 : return (132857 + x*(-1062804 + x*(3896376 + x*(-8654800 + x*(12965040 + x*(-13774464 + x*(10585344 + x*(-5829120 + x*(2154240 + x*(-394240 + x*(-67584 + (61440 - 12288*x)*x)))))))))))/4.904976384e11;
//     case 12 : return (1 + x*(-24 + x*(264 + x*(-1760 + x*(7920 + x*(-25344 + x*(59136 + x*(-101376 + x*(126720 + x*(-112640 + x*(67584 + x*(-24576 + 4096*x))))))))))))/1.9619905536e12;
//     default: return 0.0;
//     }
//   case 14: switch(i) {
//     case 0 : return (1 + x*(26 + x*(312 + x*(2288 + x*(11440 + x*(41184 + x*(109824 + x*(219648 + x*(329472 + x*(366080 + x*(292864 + x*(159744 + x*(53248 + 8192*x)))))))))))))/5.10117543936e13;
//     case 1 : return (1594309 + x*(13817102 + x*(55265496 + x*(135072080 + x*(225013360 + x*(269631648 + x*(238647552 + x*(157048320 + x*(75449088 + x*(24527360 + x*(3807232 + x*(-798720 + (-585728 - 106496*x)*x))))))))))))/5.10117543936e13;
//     case 2 : return (599191347 + x*(3077107046 + x*(7230312648 + x*(10226250320 + x*(9596180880 + x*(6154166304 + x*(2613701376 + x*(605130240 + x*(-30640896 + x*(-76510720 + x*(-23721984 + x*(-798720 + x*(1437696 + 319488*x)))))))))))))/2.55058771968e13;
//     case 3 : return (39972124843 + x*(136131829834 + x*(204337068936 + x*(172892255536 + x*(84659695120 + x*(18383260896 + x*(-3929173248 + x*(-3857677824 + x*(-855638784 + x*(120440320 + x*(100452352 + x*(12300288 + (-4100096 - 1171456*x)*x))))))))))))/2.55058771968e13;
//     case 4 : return (1295923334435 + x*(2877546594494 + x*(2520137591400 + x*(913621177040 + x*(-79613762800 + x*(-185361812064 + x*(-47479660800 + x*(9197760000 + x*(6811833600 + x*(490181120 + x*(-446617600 + x*(-96645120 + x*(14643200 + 5857280*x)))))))))))))/5.10117543936e13;
//     case 5 : return (2436916824061 + x*(3082185463214 + x*(865015251672 + x*(-509378055472 + x*(-324124703760 + x*(9331429536 + x*(44577671424 + x*(5686906368 + x*(-3564557568 + x*(-871636480 + x*(181868544 + x*(72044544 + (-5271552 - 3514368*x)*x))))))))))))/1.70039181312e13;
//     case 6 : return (1401504930291 + x*(576913893270 + x*(-461531114616 + x*(-215812774320 + x*(71937591440 + x*(39309922080 + x*(-6988430592 + x*(-4648849920 + x*(464884992 + x*(400857600 + x*(-21379072 + x*(-26357760 + x*(585728 + 1171456*x)))))))))))))/4.2509795328e12;
//     case 7 : return (1401504930291 + x*(-576913893270 + x*(-461531114616 + x*(215812774320 + x*(71937591440 + x*(-39309922080 + x*(-6988430592 + x*(4648849920 + x*(464884992 + x*(-400857600 + x*(-21379072 + x*(26357760 + (585728 - 1171456*x)*x))))))))))))/4.2509795328e12;
//     case 8 : return (2436916824061 + x*(-3082185463214 + x*(865015251672 + x*(509378055472 + x*(-324124703760 + x*(-9331429536 + x*(44577671424 + x*(-5686906368 + x*(-3564557568 + x*(871636480 + x*(181868544 + x*(-72044544 + x*(-5271552 + 3514368*x)))))))))))))/1.70039181312e13;
//     case 9 : return (1295923334435 + x*(-2877546594494 + x*(2520137591400 + x*(-913621177040 + x*(-79613762800 + x*(185361812064 + x*(-47479660800 + x*(-9197760000 + x*(6811833600 + x*(-490181120 + x*(-446617600 + x*(96645120 + (14643200 - 5857280*x)*x))))))))))))/5.10117543936e13;
//     case 10 : return (39972124843 + x*(-136131829834 + x*(204337068936 + x*(-172892255536 + x*(84659695120 + x*(-18383260896 + x*(-3929173248 + x*(3857677824 + x*(-855638784 + x*(-120440320 + x*(100452352 + x*(-12300288 + x*(-4100096 + 1171456*x)))))))))))))/2.55058771968e13;
//     case 11 : return (599191347 + x*(-3077107046 + x*(7230312648 + x*(-10226250320 + x*(9596180880 + x*(-6154166304 + x*(2613701376 + x*(-605130240 + x*(-30640896 + x*(76510720 + x*(-23721984 + x*(798720 + (1437696 - 319488*x)*x))))))))))))/2.55058771968e13;
//     case 12 : return (1594309 + x*(-13817102 + x*(55265496 + x*(-135072080 + x*(225013360 + x*(-269631648 + x*(238647552 + x*(-157048320 + x*(75449088 + x*(-24527360 + x*(3807232 + x*(798720 + x*(-585728 + 106496*x)))))))))))))/5.10117543936e13;
//     case 13 : return (1 + x*(-26 + x*(312 + x*(-2288 + x*(11440 + x*(-41184 + x*(109824 + x*(-219648 + x*(329472 + x*(-366080 + x*(292864 + x*(-159744 + (53248 - 8192*x)*x))))))))))))/5.10117543936e13;
//     default: return 0.0;
//     }
//   case 15: switch(i) {
//     case 0 : return (1 + x*(28 + x*(364 + x*(2912 + x*(16016 + x*(64064 + x*(192192 + x*(439296 + x*(768768 + x*(1025024 + x*(1025024 + x*(745472 + x*(372736 + x*(114688 + 16384*x))))))))))))))/1.4283291230208e15;
//     case 1 : return (2391477 + x*(22320312 + x*(96719532 + x*(257904192 + x*(472744272 + x*(630005376 + x*(629044416 + x*(477075456 + x*(274450176 + x*(116852736 + x*(33825792 + x*(4472832 + x*(-1118208 + (-688128 - 114688*x)*x)))))))))))))/7.141645615104e14;
//     case 2 : return (6031771195 + x*(33510074780 + x*(85965557860 + x*(134450024800 + x*(142221999920 + x*(106217151040 + x*(56180604480 + x*(19955020800 + x*(3686242560 + x*(-425384960 + x*(-497136640 + x*(-130457600 + x*(-1863680 + x*(7454720 + 1490944*x))))))))))))))/1.4283291230208e15;
//     case 3 : return (146793137441 + x*(551221068944 + x*(931383059516 + x*(919831529344 + x*(569331018256 + x*(210177839872 + x*(28534554048 + x*(-13085749248 + x*(-7809914112 + x*(-1283330048 + x*(275731456 + x*(158040064 + x*(15282176 + (-5963776 - 1490944*x)*x)))))))))))))/3.570822807552e14;
//     case 4 : return (13342139253321 + x*(34047414372972 + x*(36473961087564 + x*(19706992232928 + x*(3974856661776 + x*(-1394025657024 + x*(-1036598891328 + x*(-158485257216 + x*(59195904768 + x*(26516345856 + x*(698041344 + x*(-1648238592 + x*(-282906624 + x*(49201152 + 16400384*x))))))))))))))/1.4283291230208e15;
//     case 5 : return (52520399274139 + x*(84207579928472 + x*(44583068566036 + x*(349571430208 + x*(-8546143702096 + x*(-2499728975744 + x*(497830901568 + x*(362425350144 + x*(13760178432 + x*(-27230787584 + x*(-4347126784 + x*(1262829568 + x*(364908544 + (-32800768 - 16400384*x)*x)))))))))))))/7.141645615104e14;
//     case 6 : return (114305842384169 + x*(88734881118884 + x*(-10843418461876 + x*(-25303970627936 + x*(-2477111292656 + x*(3426500389312 + x*(690238540992 + x*(-290125575168 + x*(-84988071168 + x*(16874970112 + x*(6930187264 + x*(-680615936 + x*(-414109696 + x*(16400384 + 16400384*x))))))))))))))/4.761097076736e14;
//     case 7 : return (21022573954365 + x*x*(-8076794505780 + x*x*(1510689420240 + x*x*(-183446303040 + x*x*(16270974720 + x*x*(-1122401280 + x*x*(61501440 - 2342912*x*x)))))))/5.95137134592e13;
//     case 8 : return (114305842384169 + x*(-88734881118884 + x*(-10843418461876 + x*(25303970627936 + x*(-2477111292656 + x*(-3426500389312 + x*(690238540992 + x*(290125575168 + x*(-84988071168 + x*(-16874970112 + x*(6930187264 + x*(680615936 + x*(-414109696 + x*(-16400384 + 16400384*x))))))))))))))/4.761097076736e14;
//     case 9 : return (52520399274139 + x*(-84207579928472 + x*(44583068566036 + x*(-349571430208 + x*(-8546143702096 + x*(2499728975744 + x*(497830901568 + x*(-362425350144 + x*(13760178432 + x*(27230787584 + x*(-4347126784 + x*(-1262829568 + x*(364908544 + (32800768 - 16400384*x)*x)))))))))))))/7.141645615104e14;
//     case 10 : return (13342139253321 + x*(-34047414372972 + x*(36473961087564 + x*(-19706992232928 + x*(3974856661776 + x*(1394025657024 + x*(-1036598891328 + x*(158485257216 + x*(59195904768 + x*(-26516345856 + x*(698041344 + x*(1648238592 + x*(-282906624 + x*(-49201152 + 16400384*x))))))))))))))/1.4283291230208e15;
//     case 11 : return (146793137441 + x*(-551221068944 + x*(931383059516 + x*(-919831529344 + x*(569331018256 + x*(-210177839872 + x*(28534554048 + x*(13085749248 + x*(-7809914112 + x*(1283330048 + x*(275731456 + x*(-158040064 + x*(15282176 + (5963776 - 1490944*x)*x)))))))))))))/3.570822807552e14;
//     case 12 : return (6031771195 + x*(-33510074780 + x*(85965557860 + x*(-134450024800 + x*(142221999920 + x*(-106217151040 + x*(56180604480 + x*(-19955020800 + x*(3686242560 + x*(425384960 + x*(-497136640 + x*(130457600 + x*(-1863680 + x*(-7454720 + 1490944*x))))))))))))))/1.4283291230208e15;
//     case 13 : return (2391477 + x*(-22320312 + x*(96719532 + x*(-257904192 + x*(472744272 + x*(-630005376 + x*(629044416 + x*(-477075456 + x*(274450176 + x*(-116852736 + x*(33825792 + x*(-4472832 + x*(-1118208 + (688128 - 114688*x)*x)))))))))))))/7.141645615104e14;
//     case 14 : return (1 + x*(-28 + x*(364 + x*(-2912 + x*(16016 + x*(-64064 + x*(192192 + x*(-439296 + x*(768768 + x*(-1025024 + x*(1025024 + x*(-745472 + x*(372736 + x*(-114688 + 16384*x))))))))))))))/1.4283291230208e15;
//     default: return 0.0;
//     }
//   case 16: switch(i) {
//     case 0 : return (1 + x*(30 + x*(420 + x*(3640 + x*(21840 + x*(96096 + x*(320320 + x*(823680 + x*(1647360 + x*(2562560 + x*(3075072 + x*(2795520 + x*(1863680 + x*(860160 + x*(245760 + 32768*x)))))))))))))))/4.2849873690624e16;
//     case 1 : return (14348891 + x*(143488590 + x*(669608940 + x*(1934387000 + x*(3868541040 + x*(5672835168 + x*(6299733440 + x*(5390985600 + x*(3576418560 + x*(1827105280 + x*(698041344 + x*(181708800 + x*(20500480 + x*(-6021120 + (-3194880 - 491520*x)*x))))))))))))))/4.2849873690624e16;
//     case 2 : return (30287995733 + x*(180809647230 + x*(501981512340 + x*(857721187960 + x*(1004506623120 + x*(847659068256 + x*(524785701440 + x*(235382209920 + x*(71253262080 + x*(10457807360 + x*(-1977271296 + x*(-1540331520 + x*(-348508160 + x*(860160 + x*(18923520 + 3440640*x)))))))))))))))/4.2849873690624e16;
//     case 3 : return (4261002128223 + x*(17434223357070 + x*(32570613014940 + x*(36395666802040 + x*(26586570694320 + x*(12810612438624 + x*(3672471042240 + x*(248389764480 + x*(-271117566720 + x*(-116419663360 + x*(-14123805696 + x*(4363806720 + x*(1906544640 + x*(145367040 + (-67092480 - 14909440*x)*x))))))))))))))/4.2849873690624e16;
//     case 4 : return (133584221924461 + x*(382649001106710 + x*(477637951457940 + x*(327484288495000 + x*(120207495866640 + x*(10185195532512 + x*(-11173685082560 + x*(-4931730460800 + x*(-398033475840 + x*(301451870720 + x*(94948998144 + x*(-1104230400 + x*(-5700997120 + x*(-793927680 + x*(156549120 + 44728320*x)))))))))))))))/4.2849873690624e16;
//     case 5 : return (1435633708350799 + x*(2750959778848710 + x*(2015516182259580 + x*(526921760445080 + x*(-142558870293840 + x*(-126402864395808 + x*(-18027161472320 + x*(8709688690560 + x*(3312509840640 + x*(-105585159680 + x*(-242933763072 + x*(-25615349760 + x*(10434744320 + x*(2337054720 + (-246005760 - 98402304*x)*x))))))))))))))/4.2849873690624e16;
//     case 6 : return (6453703025399873 + x*(7136301858126870 + x*(1466842252495620 + x*(-1216963925177000 + x*(-574582910581680 + x*(57965721157344 + x*(76394795597120 + x*(4607373513600 + x*(-5982102846720 + x*(-941615234560 + x*(315259456512 + x*(80413132800 + x*(-11418767360 + x*(-4551106560 + x*(246005760 + 164003840*x)))))))))))))))/4.2849873690624e16;
//     case 7 : return (4465908195054673 + x*(1616242477522530 + x*(-1331023216783260 + x*(-537709375843640 + x*(189779779709520 + x*(87375759927456 + x*(-17132501946560 + x*(-9247752708480 + x*(1087970906880 + x*(717186229760 + x*(-50624910336 + x*(-43389265920 + x*(1701539840 + x*(2091048960 + (-35143680 - 70287360*x)*x))))))))))))))/1.4283291230208e16;
//     case 8 : return (4465908195054673 + x*(-1616242477522530 + x*(-1331023216783260 + x*(537709375843640 + x*(189779779709520 + x*(-87375759927456 + x*(-17132501946560 + x*(9247752708480 + x*(1087970906880 + x*(-717186229760 + x*(-50624910336 + x*(43389265920 + x*(1701539840 + x*(-2091048960 + x*(-35143680 + 70287360*x)))))))))))))))/1.4283291230208e16;
//     case 9 : return (6453703025399873 + x*(-7136301858126870 + x*(1466842252495620 + x*(1216963925177000 + x*(-574582910581680 + x*(-57965721157344 + x*(76394795597120 + x*(-4607373513600 + x*(-5982102846720 + x*(941615234560 + x*(315259456512 + x*(-80413132800 + x*(-11418767360 + x*(4551106560 + (246005760 - 164003840*x)*x))))))))))))))/4.2849873690624e16;
//     case 10 : return (1435633708350799 + x*(-2750959778848710 + x*(2015516182259580 + x*(-526921760445080 + x*(-142558870293840 + x*(126402864395808 + x*(-18027161472320 + x*(-8709688690560 + x*(3312509840640 + x*(105585159680 + x*(-242933763072 + x*(25615349760 + x*(10434744320 + x*(-2337054720 + x*(-246005760 + 98402304*x)))))))))))))))/4.2849873690624e16;
//     case 11 : return (133584221924461 + x*(-382649001106710 + x*(477637951457940 + x*(-327484288495000 + x*(120207495866640 + x*(-10185195532512 + x*(-11173685082560 + x*(4931730460800 + x*(-398033475840 + x*(-301451870720 + x*(94948998144 + x*(1104230400 + x*(-5700997120 + x*(793927680 + (156549120 - 44728320*x)*x))))))))))))))/4.2849873690624e16;
//     case 12 : return (4261002128223 + x*(-17434223357070 + x*(32570613014940 + x*(-36395666802040 + x*(26586570694320 + x*(-12810612438624 + x*(3672471042240 + x*(-248389764480 + x*(-271117566720 + x*(116419663360 + x*(-14123805696 + x*(-4363806720 + x*(1906544640 + x*(-145367040 + x*(-67092480 + 14909440*x)))))))))))))))/4.2849873690624e16;
//     case 13 : return (30287995733 + x*(-180809647230 + x*(501981512340 + x*(-857721187960 + x*(1004506623120 + x*(-847659068256 + x*(524785701440 + x*(-235382209920 + x*(71253262080 + x*(-10457807360 + x*(-1977271296 + x*(1540331520 + x*(-348508160 + x*(-860160 + (18923520 - 3440640*x)*x))))))))))))))/4.2849873690624e16;
//     case 14 : return (14348891 + x*(-143488590 + x*(669608940 + x*(-1934387000 + x*(3868541040 + x*(-5672835168 + x*(6299733440 + x*(-5390985600 + x*(3576418560 + x*(-1827105280 + x*(698041344 + x*(-181708800 + x*(20500480 + x*(6021120 + x*(-3194880 + 491520*x)))))))))))))))/4.2849873690624e16;
//     case 15 : return (1 + x*(-30 + x*(420 + x*(-3640 + x*(21840 + x*(-96096 + x*(320320 + x*(-823680 + x*(1647360 + x*(-2562560 + x*(3075072 + x*(-2795520 + x*(1863680 + x*(-860160 + (245760 - 32768*x)*x))))))))))))))/4.2849873690624e16;
//     default: return 0.0;
//     }
//   default: return 0.0;
//   }
// }


template<int cao_value>
__device__ REAL_TYPE caf(int i, REAL_TYPE x) {
  switch (cao_value) {
  case 1 : return 1.0;
  case 2 : {
    switch (i) {
    case 0: return 0.5-x;
    case 1: return 0.5+x;
    default:
      return 0.0;
    }
  } 
  case 3 : { 
    switch (i) {
    case 0: return 0.5*SQR(0.5 - x);
    case 1: return 0.75 - SQR(x);
    case 2: return 0.5*SQR(0.5 + x);
    default:
      return 0.0;
    }
  case 4 : { 
    switch (i) {
    case 0: return ( 1.0+x*( -6.0+x*( 12.0-x* 8.0)))/48.0;
    case 1: return (23.0+x*(-30.0+x*(-12.0+x*24.0)))/48.0;
    case 2: return (23.0+x*( 30.0+x*(-12.0-x*24.0)))/48.0;
    case 3: return ( 1.0+x*(  6.0+x*( 12.0+x* 8.0)))/48.0;
    default:
      return 0.0;
    }
  }
  case 5 : {
    switch (i) {
    case 0: return (  1.0+x*( -8.0+x*(  24.0+x*(-32.0+x*16.0))))/384.0;
    case 1: return ( 19.0+x*(-44.0+x*(  24.0+x*( 16.0-x*16.0))))/ 96.0;
    case 2: return (115.0+x*       x*(-120.0+x*       x*48.0))  /192.0;
    case 3: return ( 19.0+x*( 44.0+x*(  24.0+x*(-16.0-x*16.0))))/ 96.0;
    case 4: return (  1.0+x*(  8.0+x*(  24.0+x*( 32.0+x*16.0))))/384.0;
    default:
      return 0.0;
    }
  }
  case 6 : {
    switch (i) {
    case 0: return (  1.0+x*( -10.0+x*(  40.0+x*( -80.0+x*(  80.0-x* 32.0)))))/3840.0;
    case 1: return (237.0+x*(-750.0+x*( 840.0+x*(-240.0+x*(-240.0+x*160.0)))))/3840.0;
    case 2: return (841.0+x*(-770.0+x*(-440.0+x*( 560.0+x*(  80.0-x*160.0)))))/1920.0;
    case 3: return (841.0+x*(+770.0+x*(-440.0+x*(-560.0+x*(  80.0+x*160.0)))))/1920.0;
    case 4: return (237.0+x*( 750.0+x*( 840.0+x*( 240.0+x*(-240.0-x*160.0)))))/3840.0;
    case 5: return (  1.0+x*(  10.0+x*(  40.0+x*(  80.0+x*(  80.0+x* 32.0)))))/3840.0;
    default:
      return 0.0;
    }
  }
  case 7 : {
    switch (i) {
    case 0: return (    1.0+x*(   -12.0+x*(   60.0+x*( -160.0+x*(  240.0+x*(-192.0+x* 64.0))))))/46080.0;
    case 1: return (  361.0+x*( -1416.0+x*( 2220.0+x*(-1600.0+x*(  240.0+x*( 384.0-x*192.0))))))/23040.0;
    case 2: return (10543.0+x*(-17340.0+x*( 4740.0+x*( 6880.0+x*(-4080.0+x*(-960.0+x*960.0))))))/46080.0;
    case 3: return ( 5887.0+x*          x*(-4620.0+x*         x*( 1680.0-x*        x*320.0)))   /11520.0;
    case 4: return (10543.0+x*( 17340.0+x*( 4740.0+x*(-6880.0+x*(-4080.0+x*( 960.0+x*960.0))))))/46080.0;
    case 5: return (  361.0+x*(  1416.0+x*( 2220.0+x*( 1600.0+x*(  240.0+x*(-384.0-x*192.0))))))/23040.0;
    case 6: return (    1.0+x*(    12.0+x*(   60.0+x*(  160.0+x*(  240.0+x*( 192.0+x* 64.0))))))/46080.0;
    default:
      return 0.0;
    }
  }
  }}
  return 0.0;
}


__device__ void static Aliasing_sums_ik ( int cao, REAL_TYPE box, REAL_TYPE alpha, int mesh, int NX, int NY, int NZ,
						   REAL_TYPE *Zaehler, REAL_TYPE *Nenner ) {
  REAL_TYPE S1,S2,S3;
  REAL_TYPE fak1,fak2,zwi;
  int    MX,MY,MZ;
  REAL_TYPE NMX,NMY,NMZ;
  REAL_TYPE NM2;
  REAL_TYPE expo, TE;
  REAL_TYPE Leni = 1.0/box;

  fak1 = 1.0/ ( REAL_TYPE ) mesh;
  fak2 = SQR ( PI/ ( alpha ) );

  Zaehler[0] = Zaehler[1] = Zaehler[2] = *Nenner = 0.0;

  for ( MX = -P3M_BRILLOUIN; MX <= P3M_BRILLOUIN; MX++ ) {
    NMX = ( ( NX > mesh/2 ) ? NX - mesh : NX ) + mesh*MX;
    S1 = pow ( csinc(fak1*NMX ), 2*cao );
    for ( MY = -P3M_BRILLOUIN; MY <= P3M_BRILLOUIN; MY++ ) {
      NMY = ( ( NY > mesh/2 ) ? NY - mesh : NY ) + mesh*MY;
      S2   = S1*pow ( csinc (fak1*NMY ), 2*cao );
      for ( MZ = -P3M_BRILLOUIN; MZ <= P3M_BRILLOUIN; MZ++ ) {
	NMZ = ( ( NZ > mesh/2 ) ? NZ - mesh : NZ ) + mesh*MZ;
	S3   = S2*pow ( csinc( fak1*NMZ ), 2*cao );

	NM2 = SQR ( NMX*Leni ) + SQR ( NMY*Leni ) + SQR ( NMZ*Leni );
	*Nenner += S3;

	expo = fak2*NM2;
	TE = exp ( -expo );
	zwi  = S3 * TE/NM2;
	Zaehler[0] += NMX*zwi*Leni;
	Zaehler[1] += NMY*zwi*Leni;
	Zaehler[2] += NMZ*zwi*Leni;
      }
    }
  }
}

/* Calculate influence function */

__global__ void calculate_influence_function_device ( int cao, int mesh, REAL_TYPE box, REAL_TYPE alpha, REAL_TYPE *G_hat ) {

  const int NX = blockDim.x * blockIdx.x + threadIdx.x;
  const int NY = blockDim.y * blockIdx.y + threadIdx.y;
  const int NZ = blockDim.z * blockIdx.z + threadIdx.z;
  REAL_TYPE Dnx,Dny,Dnz;
  REAL_TYPE Zaehler[3]={0.0,0.0,0.0},Nenner=0.0;
  REAL_TYPE zwi;
  int ind = 0;
  REAL_TYPE Leni = 1.0/box;

  if((NX >= mesh) || (NY >= mesh) || (NZ >= mesh))
    return;

  ind = NX*mesh*mesh + NY * mesh + NZ;
  	  
  if ( ( NX==0 ) && ( NY==0 ) && ( NZ==0 ) )
    G_hat[ind]=0.0;
  else if ( ( NX% ( mesh/2 ) == 0 ) && ( NY% ( mesh/2 ) == 0 ) && ( NZ% ( mesh/2 ) == 0 ) )
    G_hat[ind]=0.0;
  else {
    Aliasing_sums_ik ( cao, box, alpha, mesh, NX, NY, NZ, Zaehler, &Nenner );
		  
    Dnx = ( NX > mesh/2 ) ? NX - mesh : NX;
    Dny = ( NY > mesh/2 ) ? NY - mesh : NY;
    Dnz = ( NZ > mesh/2 ) ? NZ - mesh : NZ;
	    
    zwi  = Dnx*Zaehler[0]*Leni + Dny*Zaehler[1]*Leni + Dnz*Zaehler[2]*Leni;
    zwi /= ( ( SQR ( Dnx*Leni ) + SQR ( Dny*Leni ) + SQR ( Dnz*Leni ) ) * SQR ( Nenner ) );
    G_hat[ind] = 2.0 * zwi / PI;
  }
}


//NOTE :if one wants to use the function below it requires cuda compute capability 1.3
#ifdef _P3M_GPU_REAL_DOUBLE
__device__ double atomicAdd (double* address, double val)
{
  unsigned long long int* address_as_ull =
    (unsigned long long int*)address;
  unsigned long long int old = *address_as_ull, assumed;
  do {
    assumed = old;
    old = atomicCAS(address_as_ull, assumed,
		    __double_as_longlong(val +
					 __longlong_as_double(assumed)));
  } while (assumed != old);
  return __longlong_as_double(old);
}
#endif

/** atomic add function for several cuda architectures 
 */

#if !defined __CUDA_ARCH__ || __CUDA_ARCH__ >= 200
#define THREADS_PER_BLOCK 1024
#else
#define THREADS_PER_BLOCK 512
#endif

#if !defined __CUDA_ARCH__ || __CUDA_ARCH__ >= 200 // for Fermi, atomicAdd supports floats
//atomicAdd supports floats already, do nothing
#elif __CUDA_ARCH__ >= 110
#warning Using slower atomicAdd emulation
__device__ inline void atomicAdd(float* address, float value){
  // float-atomic-add from 
  // [url="http://forums.nvidia.com/index.php?showtopic=158039&view=findpost&p=991561"]
  float old = value;
  while ((old = atomicExch(address, atomicExch(address, 0.0f)+old))!=0.0f);
}
#else
#error I need at least compute capability 1.1
#endif

__global__ void apply_diff_op( CUFFT_TYPE_COMPLEX *mesh, const int mesh_size, 
			       CUFFT_TYPE_COMPLEX *force_mesh_x,  CUFFT_TYPE_COMPLEX *force_mesh_y, CUFFT_TYPE_COMPLEX *force_mesh_z, 
			       const REAL_TYPE box ) {
  const int linear_index = mesh_size*mesh_size*blockIdx.x + mesh_size * blockIdx.y + threadIdx.x;

  if(threadIdx.x < mesh_size) {
    int n;
    n = ( threadIdx.x == mesh_size/2 ) ? 0.0 : threadIdx.x;
    n = ( n > mesh_size/2) ? n - mesh_size : n;
    weights[threadIdx.x] = n;
  }

  __syncthreads();

  const int n[3] = { weights[blockIdx.x], weights[blockIdx.y], weights[threadIdx.x] };
  const CUFFT_TYPE_COMPLEX meshw = mesh[linear_index];
  CUFFT_TYPE_COMPLEX buf;
  buf.x = -2.0 * PI * meshw.y / box;
  buf.y =  2.0 * PI * meshw.x / box;

  force_mesh_x[linear_index].x =  n[0] * buf.x;
  force_mesh_x[linear_index].y =  n[0] * buf.y;

  force_mesh_y[linear_index].x =  n[1] * buf.x;
  force_mesh_y[linear_index].y =  n[1] * buf.y;

  force_mesh_z[linear_index].x =  n[2] * buf.x;
  force_mesh_z[linear_index].y =  n[2] * buf.y;
}

__device__ inline int wrap_index(const int ind, const int mesh) {
  if(ind < 0)
    return ind + mesh;
  else if(ind >= mesh)
    return ind - mesh;
  else 
    return ind;	   
}

__global__ void apply_influence_function( CUFFT_TYPE_COMPLEX *mesh, int mesh_size, REAL_TYPE *G_hat ) {
  int linear_index = mesh_size*mesh_size*blockIdx.x + mesh_size * blockIdx.y + threadIdx.x;
  mesh[linear_index].x *= G_hat[linear_index];
  mesh[linear_index].y *= G_hat[linear_index];
}


template<int cao>
__global__ void assign_charge_kernel_shared(const CUDA_particle_data * const pdata,
				     CUFFT_TYPE_COMPLEX *mesh, const int m_size, const REAL_TYPE pos_shift, const
				     REAL_TYPE hi, int n_part, int parts_per_block) {
  const int part_in_block = threadIdx.x / cao;
  const int cao_id_x = threadIdx.x % cao;
  /** id of the particle **/
  int id = parts_per_block * (blockIdx.x*gridDim.y + blockIdx.y) + part_in_block;
  if(id >= n_part)
    return;
  /** position relative to the closest gird point **/
  REAL_TYPE m_pos[3];
  /** index of the nearest mesh point **/
  int nmp_x, nmp_y, nmp_z;      
      
  const CUDA_particle_data p = pdata[id];

  m_pos[0] = p.p[0] * hi - pos_shift;
  m_pos[1] = p.p[1] * hi - pos_shift;
  m_pos[2] = p.p[2] * hi - pos_shift;

  nmp_x = (int) floor(m_pos[0] + 0.5);
  nmp_y = (int) floor(m_pos[1] + 0.5);
  nmp_z = (int) floor(m_pos[2] + 0.5);

  m_pos[0] -= nmp_x;
  m_pos[1] -= nmp_y;
  m_pos[2] -= nmp_z;

  nmp_x = wrap_index(nmp_x +    cao_id_x, m_size);
  nmp_y = wrap_index(nmp_y + threadIdx.y, m_size);
  nmp_z = wrap_index(nmp_z + threadIdx.z, m_size);

  if((threadIdx.y < 3) && (threadIdx.z == 0)) {
    weights[3*cao*part_in_block + 3*cao_id_x + threadIdx.y] = caf<cao>(cao_id_x, m_pos[threadIdx.y]);
  }

   __syncthreads();

  atomicAdd( &(mesh[m_size*m_size*nmp_x +  m_size*nmp_y + nmp_z].x), weights[3*cao*part_in_block + 3*cao_id_x + 0]*weights[3*cao*part_in_block + 3*threadIdx.y + 1]*weights[3*cao*part_in_block + 3*threadIdx.z + 2]*p.q);
}

template<int cao>
__global__ void assign_charge_kernel(const CUDA_particle_data * const pdata,
				     CUFFT_TYPE_COMPLEX *mesh, const int m_size, const REAL_TYPE pos_shift, const
				     REAL_TYPE hi, int n_part, int parts_per_block) {  
  const int part_in_block = threadIdx.x / cao;
  const int cao_id_x = threadIdx.x % cao;
  /** id of the particle **/
  const int id = parts_per_block * (blockIdx.x + blockDim.x*blockIdx.y) + part_in_block;
  // printf("block %d %d, thread %d %d %d, id %d, p_i_b %d cao_id_x %d\n",
  // 	 blockIdx.x, blockIdx.y, threadIdx.x, threadIdx.y, threadIdx.z,
  // 	 id, part_in_block, cao_id_x);
  if(id >= n_part)
    return;
  /** position relative to the closest gird point **/
  REAL_TYPE m_pos[3];
  /** index of the nearest mesh point **/
  int nmp_x, nmp_y, nmp_z;      
      
  const CUDA_particle_data p = pdata[id];

  m_pos[0] = p.p[0] * hi - pos_shift;
  m_pos[1] = p.p[1] * hi - pos_shift;
  m_pos[2] = p.p[2] * hi - pos_shift;

  nmp_x = (int) floor(m_pos[0] + 0.5);
  nmp_y = (int) floor(m_pos[1] + 0.5);
  nmp_z = (int) floor(m_pos[2] + 0.5);

  m_pos[0] -= nmp_x;
  m_pos[1] -= nmp_y;
  m_pos[2] -= nmp_z;

  nmp_x = wrap_index(nmp_x +    cao_id_x, m_size);
  nmp_y = wrap_index(nmp_y + threadIdx.y, m_size);
  nmp_z = wrap_index(nmp_z + threadIdx.z, m_size);

  atomicAdd( &(mesh[m_size*m_size*nmp_x +  m_size*nmp_y + nmp_z].x), caf<cao>(cao_id_x, m_pos[0])*caf<cao>(threadIdx.y, m_pos[1])*caf<cao>(threadIdx.z, m_pos[2])*p.q);
}

template<>
__global__ void assign_charge_kernel<1>(const CUDA_particle_data * const pdata,
				     CUFFT_TYPE_COMPLEX *mesh, const int m_size, const REAL_TYPE pos_shift, const
				     REAL_TYPE hi, int n_part, int parts_per_block) {
  /** id of the particle **/
  int id = parts_per_block * (blockIdx.x*gridDim.y + blockIdx.y) + threadIdx.x;
  if(id >= n_part)
    return;
  /** position relative to the closest gird point **/
  REAL_TYPE m_pos[3];
  /** index of the nearest mesh point **/
  int nmp_x, nmp_y, nmp_z;      
      
  const CUDA_particle_data p = pdata[id];

  m_pos[0] = p.p[0] * hi - pos_shift;
  m_pos[1] = p.p[1] * hi - pos_shift;
  m_pos[2] = p.p[2] * hi - pos_shift;

  nmp_x = (int) floor(m_pos[0] + 0.5);
  nmp_y = (int) floor(m_pos[1] + 0.5);
  nmp_z = (int) floor(m_pos[2] + 0.5);

  m_pos[0] -= nmp_x;
  m_pos[1] -= nmp_y;
  m_pos[2] -= nmp_z;

  nmp_x = wrap_index(nmp_x, m_size);
  nmp_y = wrap_index(nmp_y, m_size);
  nmp_z = wrap_index(nmp_z, m_size);

  atomicAdd( &(mesh[m_size*m_size*nmp_x +  m_size*nmp_y + nmp_z].x), p.q);
}


void assign_charges(int n_part, const CUDA_particle_data * const pdata, CUFFT_TYPE_COMPLEX *mesh, const int m_size, const REAL_TYPE pos_shift, const
		    REAL_TYPE hi, int cao) {
  dim3 grid, block;
  grid.z = 1;
  const int cao3 = cao*cao*cao;
  int parts_per_block = 1, n_blocks = 1;

  while((parts_per_block+1)*cao3 <= THREADS_PER_BLOCK) {
    parts_per_block++;
  }
  if((n_part % parts_per_block) == 0)
    n_blocks = max(1, n_part / parts_per_block);
  else
    n_blocks = n_part / parts_per_block + 1;

  grid.x = n_blocks;
  grid.y = 1;
  while(grid.x > 65536) {
    grid.y++;
    if((n_blocks % grid.y) == 0)
      grid.x = max(1, n_blocks / grid.y);
    else
      grid.x = n_blocks / grid.y + 1;
  }

  block.x = parts_per_block * cao;
  block.y = cao;
  block.z = cao;

  // printf("n_part %d, parts_per_block %d, n_blocks %d\n", n_part, parts_per_block, n_blocks);
  // printf("grid %d %d %d block %d %d %d\n", grid.x, grid.y, grid.z, block.x, block.y, block.z);

  switch(cao) {
  case 1:
    assign_charge_kernel<1><<<grid, block>>>(pdata, mesh, m_size, pos_shift, hi, n_part, parts_per_block);
    break;
  case 2:
    assign_charge_kernel<2><<<grid, block>>>(pdata, mesh, m_size, pos_shift, hi, n_part, parts_per_block);
    break;
  case 3:
    assign_charge_kernel_shared<3><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh, m_size, pos_shift, hi, n_part, parts_per_block);
    break;
  case 4:
    assign_charge_kernel_shared<4><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh, m_size, pos_shift, hi, n_part, parts_per_block);
    break;
  case 5:
    assign_charge_kernel_shared<5><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh, m_size, pos_shift, hi, n_part, parts_per_block);
    break;
  case 6:
    assign_charge_kernel_shared<6><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh, m_size, pos_shift, hi, n_part, parts_per_block);
    break;
  case 7:
    assign_charge_kernel_shared<7><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh, m_size, pos_shift, hi, n_part, parts_per_block);
    break;
  default:
    break;
  }
  _cuda_check_errors(block, grid, "assign_charge", __FILE__, __LINE__);
}

template<int cao>
__global__ void assign_forces_kernel(const CUDA_particle_data * const pdata, CUFFT_TYPE_COMPLEX *mesh_x, CUFFT_TYPE_COMPLEX *mesh_y, CUFFT_TYPE_COMPLEX *mesh_z, const int m_size, const REAL_TYPE pos_shift, const
				     REAL_TYPE hi, float * lb_particle_force_gpu, REAL_TYPE prefactor,int n_part, int parts_per_block) {
  const int part_in_block = threadIdx.x / cao;
  const int cao_id_x = threadIdx.x % cao;
  /** id of the particle **/
  int id = parts_per_block * (blockIdx.x*gridDim.y + blockIdx.y) + part_in_block;
  if(id >= n_part)
    return;
  /** position relative to the closest gird point **/
  REAL_TYPE m_pos[3];
  /** index of the nearest mesh point **/
  int nmp_x, nmp_y, nmp_z;      

  const CUDA_particle_data p = pdata[id];

  m_pos[0] = p.p[0] * hi - pos_shift;
  m_pos[1] = p.p[1] * hi - pos_shift;
  m_pos[2] = p.p[2] * hi - pos_shift;

  nmp_x = (int) floor(m_pos[0] + 0.5);
  nmp_y = (int) floor(m_pos[1] + 0.5);
  nmp_z = (int) floor(m_pos[2] + 0.5);

  m_pos[0] -= nmp_x;
  m_pos[1] -= nmp_y;
  m_pos[2] -= nmp_z;

  nmp_x = wrap_index(nmp_x + cao_id_x, m_size);
  nmp_y = wrap_index(nmp_y + threadIdx.y, m_size);
  nmp_z = wrap_index(nmp_z + threadIdx.z, m_size);

  const int index = m_size*m_size*nmp_x +  m_size*nmp_y + nmp_z;
  const float c = -prefactor*caf<cao>(cao_id_x, m_pos[0])*caf<cao>(threadIdx.y, m_pos[1])*caf<cao>(threadIdx.z, m_pos[2])*p.q;

  atomicAdd( &(lb_particle_force_gpu[3*id+0]), c*mesh_x[index].x);      
  atomicAdd( &(lb_particle_force_gpu[3*id+1]), c*mesh_y[index].x);      
  atomicAdd( &(lb_particle_force_gpu[3*id+2]), c*mesh_z[index].x);      
}

template<int cao>
__global__ void assign_forces_kernel_shared(const CUDA_particle_data * const pdata, CUFFT_TYPE_COMPLEX *mesh_x, CUFFT_TYPE_COMPLEX *mesh_y, CUFFT_TYPE_COMPLEX *mesh_z, const int m_size, const REAL_TYPE pos_shift, const
				     REAL_TYPE hi, float * lb_particle_force_gpu, REAL_TYPE prefactor, int n_part, int parts_per_block) {
  const int part_in_block = threadIdx.x / cao;
  const int cao_id_x = threadIdx.x % cao;
  /** id of the particle **/
  int id = parts_per_block * (blockIdx.x*gridDim.y + blockIdx.y) + part_in_block;
  if(id >= n_part)
    return;
  /** position relative to the closest gird point **/
  REAL_TYPE m_pos[3];
  /** index of the nearest mesh point **/
  int nmp_x, nmp_y, nmp_z;      

  const CUDA_particle_data p = pdata[id];

  m_pos[0] = p.p[0] * hi - pos_shift;
  m_pos[1] = p.p[1] * hi - pos_shift;
  m_pos[2] = p.p[2] * hi - pos_shift;

  nmp_x = (int) floor(m_pos[0] + 0.5);
  nmp_y = (int) floor(m_pos[1] + 0.5);
  nmp_z = (int) floor(m_pos[2] + 0.5);

  m_pos[0] -= nmp_x;
  m_pos[1] -= nmp_y;
  m_pos[2] -= nmp_z;

  nmp_x = wrap_index(nmp_x + cao_id_x, m_size);
  nmp_y = wrap_index(nmp_y + threadIdx.y, m_size);
  nmp_z = wrap_index(nmp_z + threadIdx.z, m_size);

  if((threadIdx.y < 3) && (threadIdx.z == 0)) {
    weights[3*cao*part_in_block + 3*cao_id_x + threadIdx.y] = caf<cao>(cao_id_x, m_pos[threadIdx.y]);
  }

  __syncthreads();

  const int index = m_size*m_size*nmp_x +  m_size*nmp_y + nmp_z;
  const float c = -prefactor*weights[3*cao*part_in_block + 3*cao_id_x + 0]*weights[3*cao*part_in_block + 3*threadIdx.y + 1]*weights[3*cao*part_in_block + 3*threadIdx.z + 2]*p.q;
 
  atomicAdd( &(lb_particle_force_gpu[3*id+0]), c*mesh_x[index].x);      
  atomicAdd( &(lb_particle_force_gpu[3*id+1]), c*mesh_y[index].x);      
  atomicAdd( &(lb_particle_force_gpu[3*id+2]), c*mesh_z[index].x);      

}

void assign_forces(int n_part, const CUDA_particle_data * const pdata, 
		   CUFFT_TYPE_COMPLEX *mesh_x, CUFFT_TYPE_COMPLEX *mesh_y, CUFFT_TYPE_COMPLEX *mesh_z, const int m_size, 
		   const REAL_TYPE pos_shift, const REAL_TYPE hi, float * lb_particle_force_gpu, REAL_TYPE prefactor, int cao) {
  dim3 grid, block;
  grid.z = 1;

  const int cao3 = cao*cao*cao;
  int parts_per_block = 1, n_blocks = 1;

  while((parts_per_block+1)*cao3 <= 1024) {
    parts_per_block++;
  }
  if((n_part % parts_per_block) == 0)
    n_blocks = max(1, n_part / parts_per_block);
  else
    n_blocks = n_part / parts_per_block + 1;

    grid.x = n_blocks;
    grid.y = 1;
    while(grid.x > 65536) {
      grid.y++;
      if((n_blocks % grid.y) == 0)
	grid.x = max(1, n_blocks / grid.y);
      else
	grid.x = n_blocks / grid.y + 1;
    }

    block.x = parts_per_block * cao;
    block.y = cao;
    block.z = cao;

    // printf("cao %d, parts_per_block %d n_blocks %d\n", cao, parts_per_block, n_blocks);
    // printf("grid %d %d %d, block %d %d %d\n", grid.x, grid.y, grid.z, block.x, block.y, block.z);
    // printf("total threads = %d, ca points = %d\n", grid.x*grid.y*grid.z*block.x*block.y*block.z, cao3*n_part);

  switch(cao) {
  case 1:
    assign_forces_kernel<1><<<grid, block>>>(pdata, mesh_x, mesh_y, mesh_z, m_size, pos_shift, hi, lb_particle_force_gpu, prefactor, n_part, parts_per_block);
    break;
  case 2:
    assign_forces_kernel<2><<<grid, block>>>(pdata, mesh_x, mesh_y, mesh_z, m_size, pos_shift, hi, lb_particle_force_gpu, prefactor, n_part, parts_per_block);
    break;
  case 3:
    assign_forces_kernel_shared<3><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh_x, mesh_y, mesh_z, m_size, pos_shift, hi, lb_particle_force_gpu, prefactor, n_part, parts_per_block);
    break;
  case 4:
    assign_forces_kernel_shared<4><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh_x, mesh_y, mesh_z, m_size, pos_shift, hi, lb_particle_force_gpu, prefactor, n_part, parts_per_block);
    break;
  case 5:
    assign_forces_kernel_shared<5><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh_x, mesh_y, mesh_z, m_size, pos_shift, hi, lb_particle_force_gpu, prefactor, n_part, parts_per_block);
    break;
  case 6:
    assign_forces_kernel_shared<6><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh_x, mesh_y, mesh_z, m_size, pos_shift, hi, lb_particle_force_gpu, prefactor, n_part, parts_per_block);
    break;
  case 7:
    assign_forces_kernel_shared<7><<<grid, block, 3*parts_per_block*cao*sizeof(float)>>>(pdata, mesh_x, mesh_y, mesh_z, m_size, pos_shift, hi, lb_particle_force_gpu, prefactor, n_part, parts_per_block);
    break;
  default:
    break;
  }
  _cuda_check_errors(block, grid, "assign_forces", __FILE__, __LINE__);
}


extern "C" {

  /* Init the internal datastructures of the P3M GPU.
   * Mainly allocation on the device and influence function calculation.
   * Be advised: this needs mesh^3*5*sizeof(REAL_TYPE) of device memory. 
   */

  void p3m_gpu_init(int cao, int mesh, REAL_TYPE alpha, REAL_TYPE box) {
    int reinit_if = 0, mesh_changed = 0;
 
    espressoSystemInterface.requestParticleStructGpu();

    if ( this_node == 0 ) {
     
      p3m_gpu_data.npart = gpu_get_global_particle_vars_pointer_host()->number_of_particles;
      
      if((p3m_gpu_data_initialized == 0) || (p3m_gpu_data.alpha != alpha)) {
	p3m_gpu_data.alpha = alpha;
	reinit_if = 1;
      }

      if((p3m_gpu_data_initialized == 0) || (p3m_gpu_data.cao != cao)) {
	p3m_gpu_data.cao = cao;
	reinit_if = 1;
      }
	
      if((p3m_gpu_data_initialized == 0) || (p3m_gpu_data.mesh != mesh)) {
	p3m_gpu_data.mesh = mesh;
	mesh_changed = 1;
	reinit_if = 1;
      }

      if((p3m_gpu_data_initialized == 0) || (p3m_gpu_data.box != box)) {
	p3m_gpu_data.box = box;
	reinit_if = 1;
      }
     
      int mesh3 = mesh*mesh*mesh;

      if((p3m_gpu_data_initialized == 1) && (mesh_changed == 1)) {
	cudaFree(p3m_gpu_data.charge_mesh);
	cudaFree(p3m_gpu_data.force_mesh_x);
	cudaFree(p3m_gpu_data.force_mesh_y);
	cudaFree(p3m_gpu_data.force_mesh_z);
	cudaFree(p3m_gpu_data.G_hat);

	cufftDestroy(p3m_gpu_data.fft_plan);

	p3m_gpu_data_initialized = 0;
      }

      if(p3m_gpu_data_initialized == 0 && mesh > 0) {
	cudaMalloc((void **)&(p3m_gpu_data.charge_mesh),  mesh3*sizeof(CUFFT_TYPE_COMPLEX));
	cudaMalloc((void **)&(p3m_gpu_data.force_mesh_x), mesh3*sizeof(CUFFT_TYPE_COMPLEX));
	cudaMalloc((void **)&(p3m_gpu_data.force_mesh_y), mesh3*sizeof(CUFFT_TYPE_COMPLEX));
	cudaMalloc((void **)&(p3m_gpu_data.force_mesh_z), mesh3*sizeof(CUFFT_TYPE_COMPLEX));
	cudaMalloc((void **)&(p3m_gpu_data.G_hat), mesh3*sizeof(REAL_TYPE));

	cufftPlan3d(&(p3m_gpu_data.fft_plan), mesh, mesh, mesh, CUFFT_PLAN_FLAG);
      }

      if(((reinit_if == 1) || (p3m_gpu_data_initialized == 0)) && mesh > 0) {
	dim3 grid(1,1,1);
	dim3 block(1,1,1);
        block.y = mesh;
	block.z = 1;
	block.x = 512 / mesh + 1;
	grid.x = mesh / block.x + 1;
	grid.z = mesh;

	P3M_GPU_TRACE(printf("mesh %d, grid (%d %d %d), block (%d %d %d)\n", mesh, grid.x, grid.y, grid.z, block.x, block.y, block.z));
	KERNELCALL(calculate_influence_function_device,grid,block,(cao, mesh, box, alpha, p3m_gpu_data.G_hat));
      }
      p3m_gpu_data_initialized = 1;
    }
  }

  void p3m_gpu_add_farfield_force() {

    CUDA_particle_data* lb_particle_gpu;
    float* lb_particle_force_gpu;
  
    int mesh = p3m_gpu_data.mesh;
    int mesh3 = mesh*mesh*mesh;
    int cao = p3m_gpu_data.cao;
    REAL_TYPE box = p3m_gpu_data.box;

    lb_particle_gpu = gpu_get_particle_pointer();
    lb_particle_force_gpu = gpu_get_particle_force_pointer();

    p3m_gpu_data.npart = gpu_get_global_particle_vars_pointer_host()->number_of_particles;

    if(p3m_gpu_data.npart == 0)
      return;

    dim3 gridAssignment(p3m_gpu_data.npart,1,1);
    dim3 threadsAssignment(cao,cao,cao);
  
    dim3 gridConv(mesh,mesh,1);
    dim3 threadsConv(mesh,1,1);

    REAL_TYPE pos_shift = (REAL_TYPE)((cao-1)/2);
    REAL_TYPE hi = mesh/box;
    REAL_TYPE prefactor = coulomb.prefactor/(box*box*box*2.0);

    cuda_safe_mem(cudaMemset( p3m_gpu_data.charge_mesh, 0, mesh3*sizeof(CUFFT_TYPE_COMPLEX)));

    assign_charges(p3m_gpu_data.npart, lb_particle_gpu, p3m_gpu_data.charge_mesh, mesh, pos_shift, hi, cao);

    if (CUFFT_FFT(p3m_gpu_data.fft_plan, p3m_gpu_data.charge_mesh, p3m_gpu_data.charge_mesh, CUFFT_FORWARD) != CUFFT_SUCCESS){
      fprintf(stderr, "CUFFT error: ExecZ2Z Forward failed\n");
      return;
    }

    KERNELCALL( apply_influence_function, gridConv, threadsConv, (p3m_gpu_data.charge_mesh, mesh, p3m_gpu_data.G_hat));

    dim3 gridAssignment2(1,1,1);
    dim3 threadsAssignment2(1,1,1);
    if(p3m_gpu_data.npart <= 512) {
      threadsAssignment2.x = p3m_gpu_data.npart;
    } else {
      threadsAssignment2.x = 512;
      if((p3m_gpu_data.npart % 512) == 0) {
	gridAssignment2.x = p3m_gpu_data.npart / 512;
      }
      else {
	gridAssignment2.x = p3m_gpu_data.npart / 512 + 1;
      }
    }

    KERNELCALL_shared(apply_diff_op, gridConv, threadsConv, mesh*sizeof(REAL_TYPE), (p3m_gpu_data.charge_mesh, mesh, 
    										     p3m_gpu_data.force_mesh_x, p3m_gpu_data.force_mesh_y, p3m_gpu_data.force_mesh_z, box));
  
    CUFFT_FFT(p3m_gpu_data.fft_plan, p3m_gpu_data.force_mesh_x, p3m_gpu_data.force_mesh_x, CUFFT_INVERSE);
    CUFFT_FFT(p3m_gpu_data.fft_plan, p3m_gpu_data.force_mesh_y, p3m_gpu_data.force_mesh_y, CUFFT_INVERSE);
    CUFFT_FFT(p3m_gpu_data.fft_plan, p3m_gpu_data.force_mesh_z, p3m_gpu_data.force_mesh_z, CUFFT_INVERSE);

    assign_forces(p3m_gpu_data.npart, lb_particle_gpu, p3m_gpu_data.force_mesh_x, p3m_gpu_data.force_mesh_y, p3m_gpu_data.force_mesh_z,
		  mesh, pos_shift, hi, lb_particle_force_gpu, prefactor, cao);
  }

}

#endif /* ELECTROSTATICS */
