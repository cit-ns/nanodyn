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
#ifndef _P3M_H 
#define _P3M_H
/** \file p3m.h P3M algorithm for long range coulomb interaction.
 *
 *  We use a P3M (Particle-Particle Particle-Mesh) method based on the
 *  Ewald summation. Details of the used method can be found in
 *  Hockney/Eastwood and Deserno/Holm.
 *
 *  Further reading: 
 *  <ul>
 *  <li> P.P. Ewald,
 *       <i>Die Berechnung optischer und elektrostatischer Gitterpotentiale</i>,
 *       Ann. Phys. (64) 253-287, 1921
 *  <li> R. W. Hockney and J. W. Eastwood, 
 *       <i>Computer Simulation Using Particles</i>,
 *       IOP, London, 1988
 *  <li> M. Deserno and C. Holm,
 *       <i>How to mesh up {E}wald sums. I. + II.</i>,
 *       J. Chem. Phys. (109) 7678, 1998; (109) 7694, 1998
 *  <li> M. Deserno, C. Holm and H. J. Limbach,
 *       <i>How to mesh up {E}wald sums. </i>,
 *       in Molecular Dynamics on Parallel Computers,
 *       Ed. R. Esser et al., World Scientific, Singapore, 2000
 *  <li> M. Deserno,
 *       <i>Counterion condensation for rigid linear polyelectrolytes</i>,
 *       PhdThesis, Universit{\"a}t Mainz, 2000
 *  <li> J.J. Cerda, P3M for dipolar interactions. J. Chem. Phys, 129, xxx ,(2008).
 *  </ul>
 */

#include "p3m-common.h"
#include "interaction_data.h"

#ifdef P3M

/************************************************
 * data types
 ************************************************/

/** Structure to hold P3M parameters and some dependend variables. */
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
  /** number of points unto which a single charge is interpolated, i.e. p3m.cao^3 */
  int cao3;
  /** additional points around the charge assignment mesh, for method like dielectric ELC
      creating virtual charges. */
  double additional_mesh[3];
} p3m_struct;

/** P3M parameters. */
extern p3m_struct p3m;
extern local_mesh lm;
extern double* rs_mesh;
extern int p3m_sum_qpart;
extern double p3m_sum_q2;
extern double p3m_square_sum_q;

/** \name Exported Functions */
/************************************************************/
/*@{*/

/** Initialize all structures, parameters and arrays needed for the 
 *  P3M algorithm for charge-charge interactions.
 */
void  P3M_init_charges(void);

/** Updates \ref p3m_struct::alpha and \ref p3m_struct::r_cut if \ref box_l changed. */
void P3M_scaleby_box_l_charges();

/// parse the optimization parameters of p3m and the tuner
int tclcommand_inter_coulomb_parse_p3m_opt_params(Tcl_Interp * interp, int argc, char ** argv);

/// parse the basic p3m parameters
int tclcommand_inter_coulomb_parse_p3m(Tcl_Interp * interp, int argc, char ** argv);

/** compute the k-space part of forces and energies for the charge-charge interaction  **/
double P3M_calc_kspace_forces_for_charges(int force_flag, int energy_flag);

/** computer the k-space part of the stress tensor **/
void P3M_calc_kspace_stress (double* stress);

/// sanity checks
int P3M_sanity_checks();

/** checks for correctness for charges in P3M of the cao_cut, necessary when the box length changes */
int P3M_sanity_checks_boxl();

/** Calculate number of charged particles, the sum of the squared
    charges and the squared sum of the charges. */
void P3M_count_charged_particles();

/** Error Codes for p3m tuning (version 2) :
    P3M_TUNE_FAIL: force evaluation failes,
    P3M_TUNE_NO_CUTOFF: could not finde a valid realspace cutoff radius,
    P3M_TUNE_CAOTOLARGE: Charge asignment order to large for mesh size,
    P3M_TUNE_ELCTEST: conflict with ELC gap size.
*/

enum P3M_TUNE_ERROR { P3M_TUNE_FAIL = 1, P3M_TUNE_NOCUTOFF = 2, P3M_TUNE_CAOTOLARGE = 4, P3M_TUNE_ELCTEST = 8, P3M_TUNE_CUTOFF_TOO_LARGE = 16 };

/** Tune P3M parameters to desired accuracy.

    Usage:
    \verbatim inter coulomb <bjerrum> p3m tune accuracy <value> [r_cut <value> mesh <value> cao <value>] \endverbatim

    The parameters are tuned to obtain the desired accuracy in best
    time, by running mpi_integrate(0) for several parameter sets.

    The function utilizes the analytic expression of the error estimate 
    for the P3M method in the book of Hockney and Eastwood (Eqn. 8.23) in 
    order to obtain the rms error in the force for a system of N randomly 
    distributed particles in a cubic box.
    For the real space error the estimate of Kolafa/Perram is used. 

    Parameter range if not given explicit values: For \ref p3m_struct::r_cut_iL
    the function uses the values (\ref min_local_box_l -\ref #skin) /
    (n * \ref box_l), n being an integer (this implies the assumption that \ref
    p3m_struct::r_cut_iL is the largest cutoff in the system!). For \ref
    p3m_struct::mesh the function uses the two values which matches best the
    equation: number of mesh point = number of charged particles. For
    \ref p3m_struct::cao the function considers all possible values.

    For each setting \ref p3m_struct::alpha_L is calculated assuming that the
    error contributions of real and reciprocal space should be equal.

    After checking if the total error fulfils the accuracy goal the
    time needed for one force calculation (including verlet list
    update) is measured via \ref mpi_integrate (0).

    The function returns a log of the performed tuning.

    The function is based on routines of the program HE_Q.c written by M. Deserno.
 */
int tclcommand_inter_coulomb_print_p3m_tune_parameters(Tcl_Interp *interp);

/** assign the physical charges using the tabulated charge assignment function.
    If store_ca_frac is true, then the charge fractions are buffered in cur_ca_fmp and
    cur_ca_frac. */
void P3M_charge_assign();

/** assign a single charge into the current charge grid. cp_cnt gives the a running index,
    which may be smaller than 0, in which case the charge is assumed to be virtual and is not
    stored in the ca_frac arrays. */
void P3M_assign_charge(double q,
		       double real_pos[3],
		       int cp_cnt);

/** shrink wrap the charge grid */
void P3M_shrink_wrap_charge_grid(int n_charges);

/** Calculate real space contribution of coulomb pair forces.
    If NPT is compiled in, it returns the energy, which is needed for NPT. */
MDINLINE double add_p3m_coulomb_pair_force(double chgfac, double *d,double dist2,double dist,double force[3])
{
  int j;
  double fac1,fac2, adist, erfc_part_ri;
  if(dist < p3m.r_cut) {
    if (dist > 0.0){		//Vincent
      adist = p3m.alpha * dist;
#if USE_ERFC_APPROXIMATION
      erfc_part_ri = AS_erfc_part(adist) / dist;
      fac1 = coulomb.prefactor * chgfac  * exp(-adist*adist);
      fac2 = fac1 * (erfc_part_ri + 2.0*p3m.alpha*wupii) / dist2;
#else
      erfc_part_ri = erfc(adist) / dist;
      fac1 = coulomb.prefactor * chgfac;
      fac2 = fac1 * (erfc_part_ri + 2.0*p3m.alpha*wupii*exp(-adist*adist)) / dist2;
#endif
      for(j=0;j<3;j++)
	force[j] += fac2 * d[j];
      ESR_TRACE(fprintf(stderr,"%d: RSE: Pair dist=%.3f: force (%.3e,%.3e,%.3e)\n",this_node,
			dist,fac2*d[0],fac2*d[1],fac2*d[2]));
#ifdef NPT
      return fac1 * erfc_part_ri;
#endif
    }
  }
  return 0.0;
}

/** Calculate real space contribution of coulomb pair energy. */
MDINLINE double p3m_coulomb_pair_energy(double chgfac, double *d,double dist2,double dist)
{
  double adist, erfc_part_ri;

  if(dist < p3m.r_cut) {
    adist = p3m.alpha * dist;
#if USE_ERFC_APPROXIMATION
    erfc_part_ri = AS_erfc_part(adist) / dist;
    return coulomb.prefactor*chgfac*erfc_part_ri*exp(-adist*adist);
#else
    erfc_part_ri = erfc(adist) / dist;
    return coulomb.prefactor*chgfac*erfc_part_ri;
#endif
  }
  return 0.0;
}

/// print the p3m parameters to the interpreters result
int tclprint_to_result_ChargeP3M(Tcl_Interp *interp);

/** Clean up P3M memory allocations. */
void P3M_free();

#endif /* of ifdef P3M */

#endif  /*of ifndef P3M_H */
