import { BigNumber, BigNumberish } from "ethers";

const BaseMath = {
  min: (x: BigNumberish, y: BigNumberish) => {
    x = BigNumber.from(x);
    y = BigNumber.from(y);

    return x.gt(y) ? y : x;
  },
  max: (x: BigNumberish, y: BigNumberish) => {
    x = BigNumber.from(x);
    y = BigNumber.from(y);

    return x.gt(y) ? x : y;
  },
};

export default BaseMath;
