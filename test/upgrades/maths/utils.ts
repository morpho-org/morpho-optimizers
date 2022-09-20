import { BigNumber, BigNumberish } from "ethers";

export const mulDivUp = (x: BigNumberish, y: BigNumberish, scale: BigNumberish) => {
  x = BigNumber.from(x);
  y = BigNumber.from(y);
  scale = BigNumber.from(scale);
  if (x.eq(0) || y.eq(0)) return BigNumber.from(0);

  return x.mul(y).add(scale.div(2)).div(scale);
};
