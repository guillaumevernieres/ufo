/*
 * (C) Copyright 2020 UCAR
 *
 * This software is licensed under the terms of the Apache Licence Version 2.0
 * which can be obtained at http://www.apache.org/licenses/LICENSE-2.0.
 */

#include <string>

#include "ufo/obsbias/predictors/Constant.h"

#include "ioda/ObsSpace.h"

namespace ufo {

static PredictorMaker<Constant> makerFuncConstant_("constant");

// -----------------------------------------------------------------------------

Constant::Constant(const eckit::Configuration & conf)
  : PredictorBase(conf) {
}

// -----------------------------------------------------------------------------

void Constant::compute(const ioda::ObsSpace & odb,
                       const GeoVaLs &,
                       const ObsDiagnostics &,
                       const std::vector<int> & jobs,
                       Eigen::MatrixXd & out) const {
  const std::size_t njobs = jobs.size();
  const std::size_t nlocs = odb.nlocs();

  // assure shape of out
  ASSERT(out.rows() == njobs && out.cols() == nlocs);

  out.setConstant(1.0);
}

// -----------------------------------------------------------------------------

}  // namespace ufo
