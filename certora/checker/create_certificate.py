import sys
import json
from web3 import Web3, EthereumTesterProvider

w3 = Web3(EthereumTesterProvider())


# Returns the hash of a node given the hashes of its children.
def keccak_node(left_hash, right_hash):
    return w3.to_hex(
        w3.solidity_keccak(["bytes32", "bytes32"], [left_hash, right_hash])
    )


# Returns the hash of a leaf given the rewards details.
def keccak_leaf(address, amount):
    address = w3.to_checksum_address(address)
    return w3.to_hex(w3.solidity_keccak(["address", "uint256"], [address, amount]))


certificate = {}
hash_to_address = {}
hash_to_value = {}
left = {}
right = {}


# Populates the fields of the tree along the path given by the proof.
def populate(address, amount, proof):
    amount = int(amount)
    computedHash = keccak_leaf(address, amount)
    hash_to_address[computedHash] = address
    hash_to_value[computedHash] = amount
    for proofElement in proof:
        [leftHash, rightHash] = (
            [computedHash, proofElement]
            if computedHash <= proofElement
            else [proofElement, computedHash]
        )
        computedHash = keccak_node(leftHash, rightHash)
        left[computedHash] = leftHash
        right[computedHash] = rightHash
        hash_to_address[computedHash] = keccak_node(computedHash, computedHash)[:42]


# Traverse the tree and generate corresponding instruction for each internal node and each leaf.
def walk(h):
    if h in left:
        walk(left[h])
        walk(right[h])
        certificate["node"].append(
            {
                "addr": hash_to_address[h],
                "left": hash_to_address[left[h]],
                "right": hash_to_address[right[h]],
            }
        )
    else:
        certificate["leaf"].append(
            {"addr": hash_to_address[h], "value": hash_to_value[h]}
        )


with open(sys.argv[1]) as input_file:
    proofs = json.load(input_file)
    certificate["root"] = proofs["root"]
    certificate["total"] = int(proofs["total"])
    certificate["leaf"] = []
    certificate["node"] = []

    for address, data in proofs["proofs"].items():
        populate(address, data["amount"], data["proof"])

    walk(proofs["root"])

    certificate["leafLength"] = len(certificate["leaf"])
    certificate["nodeLength"] = len(certificate["node"])

    json_output = json.dumps(certificate)

with open("certificate.json", "w") as output_file:
    output_file.write(json_output)
