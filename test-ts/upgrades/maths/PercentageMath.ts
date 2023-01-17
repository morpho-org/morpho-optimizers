import { BigNumber, BigNumberish } from "ethers";

import BaseMath from "./BaseMath";
import { mulDivUp } from "./utils";

const BASE_PERCENT = BigNumber.from(100_00);
const HALF_PERCENT = BigNumber.from(50_00);

const percentMul = (x: BigNumberish, y: BigNumberish) => mulDivUp(x, y, BASE_PERCENT);

const percentDiv = (x: BigNumberish, y: BigNumberish) => mulDivUp(x, BASE_PERCENT, y);

const PercentMath = {
  BASE_PERCENT,
  percentMul,
  percentDiv,
  weightedAvg: (x: BigNumberish, y: BigNumberish, pct: BigNumberish) =>
    BaseMath.max(0, BASE_PERCENT.sub(pct)).mul(x).add(BaseMath.min(BASE_PERCENT, pct).mul(y)).add(HALF_PERCENT).div(BASE_PERCENT),
};

export default PercentMath;
