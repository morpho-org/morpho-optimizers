import { BigNumber, BigNumberish } from "ethers";

export const WAD = BigNumber.from(10).pow(18);

const CompoundMath = {
  WAD,
  mul: (x: BigNumberish, y: BigNumberish) => BigNumber.from(x).mul(y).div(WAD),
  div: (x: BigNumberish, y: BigNumberish) => WAD.mul(x).mul(WAD).div(y).div(WAD),
};

export default CompoundMath;
