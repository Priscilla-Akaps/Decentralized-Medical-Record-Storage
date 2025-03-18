import { describe, expect, it } from "vitest";
import { Cl, noneCV } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const patient = accounts.get("wallet_1")!;
const doctor = accounts.get("wallet_2")!;
const emergencyContact = accounts.get("wallet_3")!;

describe("medical records contract", () => {
  // Test adding medical record
  it("successfully adds a medical record", () => {
    const addRecordCall = simnet.callPublicFn(
      "med",
      "add-medical-record",
      [
        Cl.stringUtf8("Routine checkup - all clear"),
        Cl.stringUtf8("Central Hospital")
      ],
      patient
    );
    expect(addRecordCall.result).toBeOk(Cl.bool(true));
  });

  // Test access permissions
  it("grants and revokes access to medical records", () => {
    const grantAccessCall = simnet.callPublicFn(
      "med",
      "grant-access",
      [Cl.principal(doctor)],
      patient
    );
    expect(grantAccessCall.result).toBeOk(Cl.bool(true));

    const revokeAccessCall = simnet.callPublicFn(
      "med",
      "revoke-access",
      [Cl.principal(doctor)],
      patient
    );
    expect(revokeAccessCall.result).toBeOk(Cl.bool(true));
  });

  // Test emergency contact
  it("sets emergency contact successfully", () => {
    const setEmergencyCall = simnet.callPublicFn(
      "med",
      "set-emergency-contact",
      [Cl.principal(emergencyContact)],
      patient
    );
    expect(setEmergencyCall.result).toBeOk(Cl.bool(true));
  });

  // Test medical history
  it("adds medical history record", () => {
    const addHistoryCall = simnet.callPublicFn(
      "med",
      "add-history-record",
      [
        Cl.stringUtf8("Annual physical examination"),
        Cl.stringUtf8("City Medical Center")
      ],
      doctor
    );
    expect(addHistoryCall.result).toBeOk(Cl.bool(true));
  });

  // Test prescription management
  it("adds prescription successfully", () => {
    const addPrescriptionCall = simnet.callPublicFn(
      "med",
      "add-prescription",
      [
        Cl.stringUtf8("Amoxicillin"),
        Cl.stringUtf8("500mg twice daily"),
        Cl.uint(30)
      ],
      doctor
    );
    expect(addPrescriptionCall.result).toBeOk(Cl.bool(true));
  });

  // Test test results
  it("adds test results successfully", () => {
    const addTestResultCall = simnet.callPublicFn(
      "med",
      "add-test-result",
      [
        Cl.stringUtf8("Blood Test"),
        Cl.stringUtf8("Normal range"),
        Cl.stringUtf8("Central Lab")
      ],
      doctor
    );
    expect(addTestResultCall.result).toBeOk(Cl.bool(true));
  });

  // Test insurance information
  it("updates insurance information", () => {
    const updateInsuranceCall = simnet.callPublicFn(
      "med",
      "update-insurance",
      [
        Cl.stringUtf8("HealthCare Plus"),
        Cl.stringUtf8("HC123456"),
        Cl.uint(365)
      ],
      patient
    );
    expect(updateInsuranceCall.result).toBeOk(Cl.bool(true));
  });

  // Test allergies and conditions
  it("updates allergies and conditions", () => {
    const updateAllergiesCall = simnet.callPublicFn(
      "med",
      "update-allergies-conditions",
      [
        Cl.list([Cl.stringUtf8("Penicillin")]),
        Cl.list([Cl.stringUtf8("Asthma")])
      ],
      patient
    );
    expect(updateAllergiesCall.result).toBeOk(Cl.bool(true));
  });

  // Test record access
  it("allows authorized access to medical records", () => {
    // First grant access
    simnet.callPublicFn(
      "med",
      "grant-access",
      [Cl.principal(doctor)],
      patient
    );

    const getRecordCall = simnet.callReadOnlyFn(
      "med",
      "get-medical-record",
      [Cl.principal(patient)],
      doctor
    );
    expect(getRecordCall.result).toBeOk(noneCV());
  });

  it("denies unauthorized access to medical records", () => {
    const getRecordCall = simnet.callReadOnlyFn(
      "med",
      "get-medical-record",
      [Cl.principal(patient)],
      emergencyContact
    );
    expect(getRecordCall.result).toBeErr(Cl.uint(403));
  });
});
