// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./setup/TestSetup.sol";

contract TestPausableMarket is TestSetup {
    function testOnlyOwnerCanUpgrade() public {
        IDiamondLoupe.Facet[] memory oldFacets = IDiamondLoupe(address(diamond)).facets();
        hevm.expectRevert("LibDiamond: Must be contract owner");
        supplier1.diamondCut(address(diamond), testCuts, address(0), "");
        IDiamondCut(address(diamond)).diamondCut(testCuts, address(0), "");
        IDiamondLoupe.Facet[] memory newFacets = IDiamondLoupe(address(diamond)).facets();
        for (uint256 i = 0; i < newFacets.length; i++) {
            assertEq(newFacets[i].facetAddress, oldFacets[i].facetAddress);
            for (uint256 j = 0; j < newFacets[i].functionSelectors.length; j++) {
                assertEq(newFacets[i].functionSelectors[j], oldFacets[i].functionSelectors[j]);
            }
        }
    }

    function testReplaceFunction() public {
        bytes4[] memory fakePositionsManagerFunctionSelectors = new bytes4[](1);
        {
            uint256 index;
            fakePositionsManagerFunctionSelectors[index++] = fakePositionsManagerImpl
            .liquidate
            .selector;
        }
        IDiamondCut.FacetCut memory replaceCut = IDiamondCut.FacetCut({
            facetAddress: address(fakePositionsManagerImpl),
            action: IDiamondCut.FacetCutAction.Replace,
            functionSelectors: fakePositionsManagerFunctionSelectors
        });
        testCuts.push(replaceCut);
        IDiamondCut(address(diamond)).diamondCut(testCuts, address(0), "");
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(
                fakePositionsManagerImpl.liquidate.selector
            ),
            address(fakePositionsManagerImpl)
        );
    }

    function testRemoveFunction() public {
        bytes4[] memory fakePositionsManagerFunctionSelectors = new bytes4[](1);
        {
            uint256 index;
            fakePositionsManagerFunctionSelectors[index++] = fakePositionsManagerImpl
            .liquidate
            .selector;
        }
        IDiamondCut.FacetCut memory removeCut = IDiamondCut.FacetCut({
            facetAddress: address(0),
            action: IDiamondCut.FacetCutAction.Remove,
            functionSelectors: fakePositionsManagerFunctionSelectors
        });
        testCuts.push(removeCut);
        IDiamondCut(address(diamond)).diamondCut(testCuts, address(0), "");
        assertEq(
            IDiamondLoupe(address(diamond)).facetAddress(
                fakePositionsManagerImpl.liquidate.selector
            ),
            address(0)
        );
    }

    function testAddFunction() public {
        DummyFacet dummyFacet = new DummyFacet();
        bytes4[] memory dummyFacetFunctionSelectors = new bytes4[](1);
        {
            uint256 index;
            dummyFacetFunctionSelectors[index++] = dummyFacet.returnTrue.selector;
        }
        IDiamondCut.FacetCut memory dummyCut = IDiamondCut.FacetCut({
            facetAddress: address(dummyFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: dummyFacetFunctionSelectors
        });
        testCuts.push(dummyCut);
        IDiamondCut(address(diamond)).diamondCut(testCuts, address(0), "");
        assertTrue(DummyFacet(address(diamond)).returnTrue());
    }
}
