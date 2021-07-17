async function main() {
	const CompoundModule = await ethers.getContractFactory("CompoundModule");
	const compoudModule = await CompoundModule.deploy();

	console.log("CompoundModule deployed to:", compoudModule.address);
}

main()
.then(() => process.exit(0))
.catch((error) => {
	console.error(error);
	process.exit(1);
});