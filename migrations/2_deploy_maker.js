const UbeMaker = artifacts.require("UbeMaker");

module.exports = function (deployer) {
  deployer.deploy(
    UbeMaker,
    "0x62d5b84bE28a183aBB507E125B384122D2C25fAE",
    "0x97A9681612482A22b7877afbF8430EDC76159Cae",
    "0x00Be915B9dCf56a3CBE739D9B9c202ca692409EC",
    "0x471EcE3750Da237f93B8E339c536989b8978a438"
  );
};
