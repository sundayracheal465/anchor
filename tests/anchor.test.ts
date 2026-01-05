import { describe, expect, it } from "vitest";
import { Cl, ClarityType, ClarityValue, OptionalCV, SomeCV, TupleCV, UIntCV } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const address3 = accounts.get("wallet_3")!;
const address4 = accounts.get("wallet_4")!;

const contract = "anchor";
const itemId = 1;

const ERR_NOT_AUTHORIZED = Cl.uint(2);
const ERR_NOT_OWNER = Cl.uint(3);

const mintItem = (metadata: string) =>
  simnet.callPublicFn(contract, "mint-item", [Cl.uint(itemId), Cl.stringAscii(metadata)], address1);

const getMapEntryValue = <T extends ClarityValue>(mapName: string, key: ClarityValue): T => {
  const entry = simnet.getMapEntry(contract, mapName, key);

  if (entry.type !== ClarityType.OptionalSome || entry.value === undefined) {
    throw new Error(`expected ${mapName} entry for ${key} to exist`);
  }

  return (entry as SomeCV<T>).value;
};

const unwrapSome = <T extends ClarityValue>(optional: OptionalCV<T>): T => {
  if (optional.type !== ClarityType.OptionalSome || optional.value === undefined) {
    throw new Error("expected optional value to be Some");
  }
  return (optional as SomeCV<T>).value;
};

const getItemTuple = (): TupleCV => getMapEntryValue("items", Cl.uint(itemId));

describe("anchor contract core flows", () => {
  it("mints an item, initializes state, and emits the mint event", () => {
    const metadata = "fresh widget";

    const mintResult = mintItem(metadata);
    expect(mintResult.result).toBeOk(Cl.bool(true));

    const itemEntry = getItemTuple();
    expect(itemEntry.value.owner).toBePrincipal(address1);
    expect(itemEntry.value.metadata).toBeAscii(metadata);
    expect(itemEntry.value.status).toBeAscii("manufactured");

    const eventCount = getMapEntryValue<UIntCV>("event-counts", Cl.uint(itemId));
    expect(eventCount).toBeUint(1);

    const mintEventOptional = simnet.callReadOnlyFn(
      contract,
      "get-event",
      [Cl.uint(itemId), Cl.uint(0)],
      address1,
    );
    const mintEvent = unwrapSome(mintEventOptional.result as OptionalCV<TupleCV>);

    expect(mintEvent.value.actor).toBePrincipal(address1);
    expect(mintEvent.value.kind).toBeAscii("mint");
    expect(mintEvent.value.note).toBeSome(Cl.stringAscii("minted"));
    expect(mintEvent.value.status).toBeSome(Cl.stringAscii("manufactured"));
    expect(mintEvent.value.metadata).toBeSome(Cl.stringAscii(metadata));
    expect(mintEvent.value["new-owner"]).toBeNone();
  });

  it("requires authorization for custom events and records status history", () => {
    const metadata = "tracked package";
    const customNote = "scanned by operator";
    const updatedStatus = "in-transit";

    mintItem(metadata);

    const unauthorizedAppend = simnet.callPublicFn(
      contract,
      "append-event",
      [Cl.uint(itemId), Cl.stringAscii(customNote)],
      address2,
    );
    expect(unauthorizedAppend.result).toBeErr(ERR_NOT_AUTHORIZED);

    const authorizeResult = simnet.callPublicFn(
      contract,
      "authorize-actor",
      [Cl.uint(itemId), Cl.standardPrincipal(address2)],
      address1,
    );
    expect(authorizeResult.result).toBeOk(Cl.bool(true));

    const appendResult = simnet.callPublicFn(
      contract,
      "append-event",
      [Cl.uint(itemId), Cl.stringAscii(customNote)],
      address2,
    );
    expect(appendResult.result).toBeOk(Cl.bool(true));

    const eventCountAfterAppend = getMapEntryValue<UIntCV>("event-counts", Cl.uint(itemId));
    expect(eventCountAfterAppend).toBeUint(2);

    const latestEventOptional = simnet.callReadOnlyFn(contract, "get-latest-event", [Cl.uint(itemId)], address1);
    const latestEvent = unwrapSome(latestEventOptional.result as OptionalCV<TupleCV>);
    expect(latestEvent.value.actor).toBePrincipal(address2);
    expect(latestEvent.value.kind).toBeAscii("custom");
    expect(latestEvent.value.note).toBeSome(Cl.stringAscii(customNote));
    expect(latestEvent.value.status).toBeNone();

    const statusResult = simnet.callPublicFn(
      contract,
      "update-status",
      [Cl.uint(itemId), Cl.stringAscii(updatedStatus)],
      address2,
    );
    expect(statusResult.result).toBeOk(Cl.bool(true));

    const updatedItem = getItemTuple();
    expect(updatedItem.value.status).toBeAscii(updatedStatus);

    const eventCountAfterStatus = getMapEntryValue<UIntCV>("event-counts", Cl.uint(itemId));
    expect(eventCountAfterStatus).toBeUint(3);

    const statusHistoryOptional = simnet.callReadOnlyFn(
      contract,
      "get-status-history",
      [Cl.uint(itemId), Cl.uint(0)],
      address1,
    );
    const statusHistory = unwrapSome(statusHistoryOptional.result as OptionalCV<TupleCV>);
    expect(statusHistory.value.status).toBeAscii(updatedStatus);
    expect(statusHistory.value.actor).toBePrincipal(address2);
    expect(statusHistory.value["event-index"]).toBeUint(2);
  });

  it("transfers ownership, invalidates prior approvals, and allows reauthorization", () => {
    const metadata = "transferrable crate";
    const deliveryNote = "delivery confirmed";
    const deliveredStatus = "delivered";

    mintItem(metadata);

    const unauthorizedTransfer = simnet.callPublicFn(
      contract,
      "transfer-ownership",
      [Cl.uint(itemId), Cl.standardPrincipal(address3)],
      address2,
    );
    expect(unauthorizedTransfer.result).toBeErr(ERR_NOT_OWNER);

    const authorizeResult = simnet.callPublicFn(
      contract,
      "authorize-actor",
      [Cl.uint(itemId), Cl.standardPrincipal(address2)],
      address1,
    );
    expect(authorizeResult.result).toBeOk(Cl.bool(true));

    const transferResult = simnet.callPublicFn(
      contract,
      "transfer-ownership",
      [Cl.uint(itemId), Cl.standardPrincipal(address3)],
      address1,
    );
    expect(transferResult.result).toBeOk(Cl.bool(true));

    const ownerEntry = getItemTuple();
    expect(ownerEntry.value.owner).toBePrincipal(address3);

    const versionAfterTransfer = getMapEntryValue<UIntCV>("item-versions", Cl.uint(itemId));
    expect(versionAfterTransfer).toBeUint(1);

    const transferEventOptional = simnet.callReadOnlyFn(
      contract,
      "get-event",
      [Cl.uint(itemId), Cl.uint(1)],
      address3,
    );
    const transferEvent = unwrapSome(transferEventOptional.result as OptionalCV<TupleCV>);
    expect(transferEvent.value.kind).toBeAscii("ownership-transfer");
    expect(transferEvent.value["new-owner"]).toBeSome(Cl.standardPrincipal(address3));

    const postTransferAuthorized = simnet.callReadOnlyFn(
      contract,
      "is-actor-authorized",
      [Cl.uint(itemId), Cl.standardPrincipal(address2)],
      address3,
    );
    expect(postTransferAuthorized.result).toBeBool(false);

    const newOwnerAuthorize = simnet.callPublicFn(
      contract,
      "authorize-actor",
      [Cl.uint(itemId), Cl.standardPrincipal(address4)],
      address3,
    );
    expect(newOwnerAuthorize.result).toBeOk(Cl.bool(true));

    const newAuthorizationCheck = simnet.callReadOnlyFn(
      contract,
      "is-actor-authorized",
      [Cl.uint(itemId), Cl.standardPrincipal(address4)],
      address3,
    );
    expect(newAuthorizationCheck.result).toBeBool(true);

    const appendAfterTransfer = simnet.callPublicFn(
      contract,
      "append-event",
      [Cl.uint(itemId), Cl.stringAscii(deliveryNote)],
      address4,
    );
    expect(appendAfterTransfer.result).toBeOk(Cl.bool(true));

    const statusUpdateAfterTransfer = simnet.callPublicFn(
      contract,
      "update-status",
      [Cl.uint(itemId), Cl.stringAscii(deliveredStatus)],
      address4,
    );
    expect(statusUpdateAfterTransfer.result).toBeOk(Cl.bool(true));

    const finalEventCount = getMapEntryValue<UIntCV>("event-counts", Cl.uint(itemId));
    expect(finalEventCount).toBeUint(4);

    const finalItemEntry = getItemTuple();
    expect(finalItemEntry.value.status).toBeAscii(deliveredStatus);
    expect(finalItemEntry.value.owner).toBePrincipal(address3);

    const latestStatusHistoryOptional = simnet.callReadOnlyFn(
      contract,
      "get-status-history",
      [Cl.uint(itemId), Cl.uint(0)],
      address3,
    );
    const latestHistory = unwrapSome(latestStatusHistoryOptional.result as OptionalCV<TupleCV>);
    expect(latestHistory.value.status).toBeAscii(deliveredStatus);
    expect(latestHistory.value.actor).toBePrincipal(address4);
    expect(latestHistory.value["event-index"]).toBeUint(3);

    const latestEventOptional = simnet.callReadOnlyFn(contract, "get-latest-event", [Cl.uint(itemId)], address3);
    const latestEvent = unwrapSome(latestEventOptional.result as OptionalCV<TupleCV>);
    expect(latestEvent.value.kind).toBeAscii("status-update");
    expect(latestEvent.value.status).toBeSome(Cl.stringAscii(deliveredStatus));
    expect(latestEvent.value.actor).toBePrincipal(address4);
  });
});
