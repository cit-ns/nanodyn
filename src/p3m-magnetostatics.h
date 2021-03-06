/*
  Copyright (C) 2010,2011 The ESPResSo project
  Copyright (C) 2002,2003,2004,2005,2006,2007,2008,2009,2010 
    Max-Planck-Institute for Polymer Research, Theory Group
  
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
#ifndef _P3M_MAGNETOSTATICS_H
#define _P3M_MAGNETOSTATICS_H
/** \file p3m-magnetostatics.h P3M algorithm for long range magnetic dipole-dipole interaction.
 *
 *  We use here a P3M (Particle-Particle Particle-Mesh) method based
 *  on the dipolar Ewald summation. Details of the used method can be found in
 *  Hockney/Eastwood and Deserno/Holm. The file p3m contains only the
 *  Particle-Mesh part.
 *
 *  Further reading: 
 *  <ul>
 *  <li> J.J. Cerda, P3M for dipolar interactions. J. Chem. Phys, 129, xxx ,(2008).
 *  </ul>
 *
 */
#include "p3m-common.h"
#include "interaction_data.h"

#ifdef DP3M

/** Structure to hold dipolar P3M parameters and some dependend variables. */
typedef struct {
    /** Ewald splitting parameter (0<alpha<1), rescaled to alpha_L = alpha * box_l. */
  double alpha_L;
  /** Cutoff radius for real space electrostatics (>0), rescaled to r_cut_iL = r_cut * box_l_i. */
  double r_cut_iL;
  /** number of mesh points per coordinate direction (>0). */
  int    mesh[3];
  /** offset of the first mesh point (lower left 
      corner) from the coordinate origin ([0,1[). */
  double mesh_off[3];
  /** charge assignment order ([0,7]). */
  int    cao;
  /** number of interpolation points for charge assignment function */
  int    inter;
  /** Accuracy of the actual parameter set. */
  double accuracy;

  /** epsilon of the "surrounding dielectric". */
  double epsilon;
  /** Cutoff for charge assignment. */
  double cao_cut[3];
  /** mesh constant. */
  double a[3];
  /** inverse mesh constant. */
  double ai[3];
  /** unscaled \ref alpha_L for use with fast inline functions only */
  double alpha;
  /** unscaled \ref r_cut_iL for use with fast inline functions only */
  double r_cut;
  /** full size of the interpolated assignment function */
  int inter2;
  /** number of points unto which a single charge is interpolated, i.e. Dp3m.cao^3 */
  int cao3;
  /** additional points around the charge assignment mesh, for method like dielectric ELC
      creating virtual charges. */
  double additional_mesh[3];
} Dp3m_struct;

/** dipolar P3M parameters. */
extern Dp3m_struct Dp3m;

extern void Drealloc_ca_fields(int newsize);

/** \name Exported Functions */
/************************************************************/
/*@{*/
/** dipolar p3m parser */
int tclcommand_inter_magnetic_parse_p3m(Tcl_Interp * interp, int argc, char ** argv);

/** dipolar p3m parser, optional parameters */
int tclcommand_inter_magnetic_parse_p3m_opt_params(Tcl_Interp * interp, int argc, char ** argv);

/** print the p3m parameters to the interpreters result */
int tclprint_to_result_DipolarP3M(Tcl_Interp *interp);

/** Initialize all structures, parameters and arrays needed for the 
 *  P3M algorithm for dipole-dipole interactions.
 */
void  P3M_init_dipoles(void);

/** Updates \ref Dp3m_struct::alpha and \ref Dp3m_struct::r_cut if \ref box_l changed. */
void P3M_scaleby_box_l_dipoles();

/// sanity checks
int DP3M_sanity_checks();

/** assign the physical dipoles using the tabulated assignment function.
    If Dstore_ca_frac is true, then the charge fractions are buffered in Dcur_ca_fmp and
    Dcur_ca_frac. */
void P3M_dipole_assign(void);


/** compute the k-space part of forces and energies for the magnetic dipole-dipole interaction  */
double P3M_calc_kspace_forces_for_dipoles(int force_flag, int energy_flag);


/** Calculate number of magnetic  particles, the sum of the squared
    charges and the squared sum of the charges. */

void P3M_count_magnetic_particles();


/** assign a single dipole into the current charge grid. cp_cnt gives the a running index,
    which may be smaller than 0, in which case the charge is assumed to be virtual and is not
    stored in the Dca_frac arrays. */
void P3M_assign_dipole(double real_pos[3],double mu, double dip[3],int cp_cnt);

/** shrink wrap the dipoles grid */
void DP3M_shrink_wrap_dipole_grid(int n_dipoles);

/** Calculate real space contribution of p3m dipolar pair forces and torques.
    If NPT is compiled in, it returns the energy, which is needed for NPT. */
MDINLINE double add_p3m_dipolar_pair_force(Particle *p1, Particle *p2,
					   double *d,double dist2,double dist,double force[3])
{
  int j;
#ifdef NPT
  double fac1;
#endif
  double adist, erfc_part_ri, coeff, exp_adist2, dist2i;
  double mimj, mir, mjr;
  double B_r, C_r, D_r;
  double alpsq = Dp3m.alpha * Dp3m.alpha;
  double mixmj[3], mixr[3], mjxr[3];

  if(dist < Dp3m.r_cut && dist > 0) {
    adist = Dp3m.alpha * dist;
    #if USE_ERFC_APPROXIMATION
       erfc_part_ri = AS_erfc_part(adist) / dist;
    #else
       erfc_part_ri = erfc(adist) / dist;
    #endif

  //Calculate scalar multiplications for vectors mi, mj, rij
  mimj = p1->r.dip[0]*p2->r.dip[0] + p1->r.dip[1]*p2->r.dip[1] + p1->r.dip[2]*p2->r.dip[2];
  mir = p1->r.dip[0]*d[0] + p1->r.dip[1]*d[1] + p1->r.dip[2]*d[2];
  mjr = p2->r.dip[0]*d[0] + p2->r.dip[1]*d[1] + p2->r.dip[2]*d[2];

  coeff = 2.0*Dp3m.alpha*wupii;
  dist2i = 1 / dist2;
  exp_adist2 = exp(-adist*adist);

  if(Dp3m.accuracy > 5e-06)
    B_r = (erfc_part_ri + coeff) * exp_adist2 * dist2i;
  else
    B_r = (erfc(adist)/dist + coeff * exp_adist2) * dist2i;
    
  C_r = (3*B_r + 2*alpsq*coeff*exp_adist2) * dist2i;
  D_r = (5*C_r + 4*coeff*alpsq*alpsq*exp_adist2) * dist2i;

  // Calculate real-space forces
  for(j=0;j<3;j++)
    force[j] += coulomb.Dprefactor *((mimj*d[j] + p1->r.dip[j]*mjr + p2->r.dip[j]*mir) * C_r - mir*mjr*D_r*d[j]) ;

  //Calculate vector multiplications for vectors mi, mj, rij

  mixmj[0] = p1->r.dip[1]*p2->r.dip[2] - p1->r.dip[2]*p2->r.dip[1];
  mixmj[1] = p1->r.dip[2]*p2->r.dip[0] - p1->r.dip[0]*p2->r.dip[2];
  mixmj[2] = p1->r.dip[0]*p2->r.dip[1] - p1->r.dip[1]*p2->r.dip[0];

  mixr[0] = p1->r.dip[1]*d[2] - p1->r.dip[2]*d[1];
  mixr[1] = p1->r.dip[2]*d[0] - p1->r.dip[0]*d[2];
  mixr[2] = p1->r.dip[0]*d[1] - p1->r.dip[1]*d[0];

  mjxr[0] = p2->r.dip[1]*d[2] - p2->r.dip[2]*d[1];
  mjxr[1] = p2->r.dip[2]*d[0] - p2->r.dip[0]*d[2];
  mjxr[2] = p2->r.dip[0]*d[1] - p2->r.dip[1]*d[0];

  // Calculate real-space torques
#ifdef ROTATION
  for(j=0;j<3;j++){
    p1->f.torque[j] += coulomb.Dprefactor *(-mixmj[j]*B_r + mixr[j]*mjr*C_r);
    p2->f.torque[j] += coulomb.Dprefactor *( mixmj[j]*B_r + mjxr[j]*mir*C_r);
  }
#endif
#ifdef NPT
#if USE_ERFC_APPROXIMATION
  fac1 = coulomb.Dprefactor * p1->p.dipm*p2->p.dipm * exp(-adist*adist);
#else
  fac1 = coulomb.Dprefactor * p1->p.dipm*p2->p.dipm;
#endif
  return fac1 * ( mimj*B_r - mir*mjr * C_r );
#endif
  }
  return 0.0;
}

/** Calculate real space contribution of dipolar pair energy. */
MDINLINE double p3m_dipolar_pair_energy(Particle *p1, Particle *p2,
					double *d,double dist2,double dist)
{
  double /* fac1,*/ adist, erfc_part_ri, coeff, exp_adist2, dist2i;
  double mimj, mir, mjr;
  double B_r, C_r;
  double alpsq = Dp3m.alpha * Dp3m.alpha;
 
  if(dist < Dp3m.r_cut && dist > 0) {
    adist = Dp3m.alpha * dist;
    /*fac1 = coulomb.Dprefactor;*/

#if USE_ERFC_APPROXIMATION
    erfc_part_ri = AS_erfc_part(adist) / dist;
    /*  fac1 = coulomb.Dprefactor * p1->p.dipm*p2->p.dipm; IT WAS WRONG */ /* *exp(-adist*adist); */ 
#else
    erfc_part_ri = erfc(adist) / dist;
    /* fac1 = coulomb.Dprefactor * p1->p.dipm*p2->p.dipm;  IT WAS WRONG*/
#endif

    //Calculate scalar multiplications for vectors mi, mj, rij
    mimj = p1->r.dip[0]*p2->r.dip[0] + p1->r.dip[1]*p2->r.dip[1] + p1->r.dip[2]*p2->r.dip[2];
    mir = p1->r.dip[0]*d[0] + p1->r.dip[1]*d[1] + p1->r.dip[2]*d[2];
    mjr = p2->r.dip[0]*d[0] + p2->r.dip[1]*d[1] + p2->r.dip[2]*d[2];

    coeff = 2.0*Dp3m.alpha*wupii;
    dist2i = 1 / dist2;
    exp_adist2 = exp(-adist*adist);

    if(Dp3m.accuracy > 5e-06)
      B_r = (erfc_part_ri + coeff) * exp_adist2 * dist2i;
    else
      B_r = (erfc(adist)/dist + coeff * exp_adist2) * dist2i;
  
    C_r = (3*B_r + 2*alpsq*coeff*exp_adist2) * dist2i;

    /*
      printf("(%4i %4i) pair energy = %f (B_r=%15.12f C_r=%15.12f)\n",p1->p.identity,p2->p.identity,fac1*(mimj*B_r-mir*mjr*C_r),B_r,C_r);
    */
  
    /* old line return fac1 * ( mimj*B_r - mir*mjr * C_r );*/
    return coulomb.Dprefactor * ( mimj*B_r - mir*mjr * C_r );
  }
  return 0.0;
}

#endif /* DP3M */
#endif /* _P3M_DIPOLES_H */
