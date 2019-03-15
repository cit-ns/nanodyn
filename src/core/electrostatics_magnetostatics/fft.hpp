/*
  Copyright (C) 2010-2018 The ESPResSo project
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
#ifndef _FFT_H
#define _FFT_H
/** \file
 *
 *  Routines, row decomposition, data structures and communication for the
 * 3D-FFT.
 *
 *  The 3D-FFT is split into 3 ond dimensional FFTs. The data is
 *  distributed in such a way, that for the actual direction of the
 *  FFT each node has a certain number of rows for which it performs a
 *  1D-FFT. After performing the FFT on that direction the data is
 *  redistributed.
 *
 *  For simplicity at the moment I have implemented a full complex to
 *  complex FFT (even though a real to complex FFT would be
 *  sufficient)
 *
 *  \todo Combine the forward and backward structures.
 *  \todo The packing routines could be moved to utils.hpp when they are needed
 * elsewhere.
 *
 *  For more information about FFT usage, see \ref fft.cpp "fft.cpp".
 */

#include "config.hpp"
#if defined(P3M) || defined(DP3M)

#include "fft-common.hpp"

/** \name Exported Functions */
/************************************************************/
/*@{*/

/** Initialize everything connected to the 3D-FFT.

 * \return Maximal size of local fft mesh (needed for allocation of ca_mesh).
 * \param data            Pointer Pointer to data array.
 * \param ca_mesh_dim     Pointer to local CA mesh dimensions.
 * \param ca_mesh_margin  Pointer to local CA mesh margins.
 * \param global_mesh_dim Pointer to global CA mesh dimensions.
 * \param global_mesh_off Pointer to global CA mesh offset.
 * \param ks_pnum         Pointer to number of permutations in k-space.
 */
int fft_init(double **data, int *ca_mesh_dim, int *ca_mesh_margin, int *global_mesh_dim, double *global_mesh_off,
             int *ks_pnum, fft_data_struct &fft, const Vector3i &grid);

/** perform the forward 3D FFT.
    The assigned charges are in \a data. The result is also stored in \a data.
    \warning The content of \a data is overwritten.
    \param data Mesh.
*/
void fft_perform_forw(double *data, fft_data_struct &fft);

/** perform the backward 3D FFT.
    \warning The content of \a data is overwritten.
    \param data Mesh.
*/
void fft_perform_back(double *data, bool check_complex, fft_data_struct &fft);

/*@}*/
#endif

#endif
