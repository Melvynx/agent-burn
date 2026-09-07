import Foundation
import ServiceManagement
import Testing

@testable import AgentBurn

@Test @MainActor func loginItemFollowsSystemStatusAndCanBeDisabled() async {
  var systemStatus = SMAppService.Status.notRegistered
  let item = LoginItem(
    readStatus: { systemStatus }, register: { systemStatus = .enabled },
    unregister: { systemStatus = .notRegistered })
  #expect(!item.isEnabled)
  await item.setEnabled(true)
  #expect(item.isEnabled)
  systemStatus = .requiresApproval
  item.refresh()
  #expect(item.requiresApproval)
  #expect(item.isEnabled)
  await item.setEnabled(false)
  #expect(!item.isEnabled)
  #expect(!item.requiresApproval)
}

@Test @MainActor func loginItemFailureDoesNotPretendItIsEnabled() async {
  let item = LoginItem(
    readStatus: { .notRegistered },
    register: { throw NSError(domain: "LoginItemTest", code: 1) }, unregister: {})
  await item.setEnabled(true)
  #expect(!item.isEnabled)
  #expect(item.errorMessage != nil)
  #expect(!item.isUpdating)
}
