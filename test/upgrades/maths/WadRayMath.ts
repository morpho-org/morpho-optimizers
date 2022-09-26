import { BigNumber, BigNumberish } from "ethers";

import { mulDivUp } from "./utils";

export const WAD = BigNumber.from(10).pow(18);
export const RAY = BigNumber.from(10).pow(27);

const WadRayMath = {
  WAD,
  RAY,
  wadMul: (x: BigNumberish, y: BigNumberish) => mulDivUp(x, y, WAD),
  wadDiv: (x: BigNumberish, y: BigNumberish) => mulDivUp(x, WAD, y),
  rayMul: (x: BigNumberish, y: BigNumberish) => mulDivUp(x, y, RAY),
  rayDiv: (x: BigNumberish, y: BigNumberish) => mulDivUp(x, RAY, y),
};

export default WadRayMath;
