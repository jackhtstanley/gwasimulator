# cython: linetrace=False
# cython: profile=False
# cython: binding=False
# cython: boundscheck=False
# cython: wraparound=False
# cython: initializedcheck=False
# cython: nonecheck=False
# cython: language_level=3
# cython: infer_types=True

from cython.parallel import prange
from libc.math cimport exp
import numpy as np
cimport numpy as np


def zarr_islice(arr, start=None, end=None):

    """
    This is copied from the official, but not yet released implementation of
    i_slice from the official Zarr codebase:
    https://github.com/zarr-developers/zarr-python/blob/e79e75ca8f07c95a5deede51f7074f699aa41149/zarr/core.py#L463
    :param arr:
    :param start:
    :param end:
    :return:
    """

    if len(arr.shape) == 0:
        # Same error as numpy
        raise TypeError("iteration over a 0-d array")
    if start is None:
        start = 0
    if end is None or end > arr.shape[0]:
        end = arr.shape[0]

    cdef unsigned int j, chunk_size = arr.chunks[0]
    chunk = None

    for j in range(start, end):
        if j % chunk_size == 0:
            chunk = arr[j: j + chunk_size]
        elif chunk is None:
            chunk_start = j - j % chunk_size
            chunk_end = chunk_start + chunk_size
            chunk = arr[chunk_start:chunk_end]
        yield chunk[j % chunk_size]


cpdef find_ld_block_boundaries(long[:] pos, long[:, :] block_boundaries, int n_threads):

    cdef unsigned int i, j, ldb_idx, block_start, block_end, B = len(block_boundaries), M = len(pos)
    cdef long[:] v_min = np.zeros_like(pos, dtype=np.int)
    cdef long[:] v_max = M*np.ones_like(pos, dtype=np.int)

    for i in prange(M, nogil=True, schedule='static', num_threads=n_threads):

        # Find the positional boundaries for SNP i:
        for ldb_idx in range(B):
            if block_boundaries[ldb_idx, 0] <= pos[i] < block_boundaries[ldb_idx, 1]:
                block_start, block_end = block_boundaries[ldb_idx, 0], block_boundaries[ldb_idx, 1]
                break

        for j in range(i, M):
            if pos[j] >= block_end:
                v_max[i] = j
                break

        for j in range(i, 0, -1):
            if pos[j] < block_start:
                v_min[i] = j + 1
                break

    return np.array((v_min, v_max))


cpdef find_windowed_ld_boundaries(double[:] cm_dist, double max_dist, int n_threads):

    cdef unsigned int i, j, M = len(cm_dist)
    cdef long[:] v_min = np.zeros_like(cm_dist, dtype=np.int)
    cdef long[:] v_max = M*np.ones_like(cm_dist, dtype=np.int)

    for i in prange(M, nogil=True, schedule='static', num_threads=n_threads):

        for j in range(i, M):
            if cm_dist[j] - cm_dist[i] > max_dist:
                v_max[i] = j
                break

        for j in range(i, 0, -1):
            if cm_dist[i] - cm_dist[j] > max_dist:
                v_min[i] = j + 1
                break

    return np.array((v_min, v_max))


cpdef find_shrinkage_ld_boundaries(double[:] cm_dist,
                                   double genmap_Ne,
                                   int genmap_sample_size,
                                   double cutoff,
                                   int n_threads):

    cdef unsigned int i, j, M = len(cm_dist)
    cdef long[:] v_min = np.zeros_like(cm_dist, dtype=np.int)
    cdef long[:] v_max = M*np.ones_like(cm_dist, dtype=np.int)

    # The multiplicative factor for the shrinkage estimator
    cdef double mult_factor = 2. * genmap_Ne / genmap_sample_size

    for i in prange(M, nogil=True, schedule='static', num_threads=n_threads):

        for j in range(i, M):
            if exp(-mult_factor*(cm_dist[j] - cm_dist[i])) < cutoff:
                v_max[i] = j
                break

        for j in range(i, 0, -1):
            if exp(-mult_factor*(cm_dist[i] - cm_dist[j])) < cutoff:
                v_min[i] = j + 1
                break

    return np.array((v_min, v_max))
