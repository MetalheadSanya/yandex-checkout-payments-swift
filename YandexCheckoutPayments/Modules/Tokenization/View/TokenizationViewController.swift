import class PassKit.PKPaymentAuthorizationViewController
import FunctionalSwift
import UIKit

protocol Presentable {
    var iPhonePresentationStyle: PresentationStyle { get }
    var iPadPresentationStyle: PresentationStyle { get }
    var hasNavigationBar: Bool { get }
}

enum PresentationStyle {
    case actionSheet
    case pageSheet
    case modal
    case applePay
}

private let timeInterval = TimeInterval(UINavigationControllerHideShowBarDuration)

class TokenizationViewController: UIViewController {

    // MARK: - VIPER module properties

    var output: (TokenizationViewOutput & TokenizationModuleInput)!

    // MARK: - Container properties

    var modules: [UIViewController] = []

    private weak var actionSheetTemplate: ActionSheetTemplate?
    private weak var modalTemplate: ModalTemplate?
    private weak var pageSheetTemplate: PageSheetTemplate?

    private var containerConstraints: [NSLayoutConstraint] = []

    // MARK: - Managing Child View Controllers in a Custom Container

    override var shouldAutomaticallyForwardAppearanceMethods: Bool {
        return false
    }

    // MARK: - Configuring the View Rotation Settings

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {

        let result: UIInterfaceOrientationMask

        if UIDevice.current.isIphonePlus {
            result = .allButUpsideDown
        } else if case .pad = UIDevice.current.userInterfaceIdiom {
            result = .all
        } else {
            result = .portrait
        }

        return result
    }

    // MARK: - Managing the View

    override func viewDidLoad() {
        super.viewDidLoad()
        output.setupView()

        if UIDevice.current.isIphonePlus == false {
            // https://stackoverflow.com/a/26358192/6108456
            // The only option of forced transfer to portrait mode.
            let value = UIInterfaceOrientation.portrait.rawValue
            UIDevice.current.setValue(value, forKey: "orientation")
        }
    }

    // MARK: - Presenting View Controllers

    // swiftlint:disable cyclomatic_complexity
    override func show(_ vc: UIViewController, sender: Any?) {

        let style = getStyle(vc)

        if let previous = modules.last,
           let actionSheet = actionSheetTemplate,
           case .actionSheet = style {
            pushActionSheet(actionSheet, previous: previous, next: vc, sender: sender)
        } else if let previous = modules.last,
                  let pageSheet = pageSheetTemplate,
                  case .pageSheet = style {
            pushPageSheet(pageSheet, previous: previous, next: vc, sender: sender)
        } else if let previous = modules.last,
                  let modal = modalTemplate,
                  case .modal = style {
            pushModal(modal, previous: previous, next: vc, sender: sender)
        } else if modules.last != nil,
                  let actionSheet = actionSheetTemplate,
                  case .modal = style {
            hideAnimated(actionSheet: actionSheet) {
                self.presentModalAnimated(vc)
            }
        } else if modules.last != nil,
                  let actionSheet = actionSheetTemplate,
                  case .applePay = style {
            // From ActionSheet to ApplePay
            hideAnimated(actionSheet: actionSheet) {
                self.showApplePay(vc)
            }
        } else if modules.last != nil,
                  let pageSheet = pageSheetTemplate,
                  case .applePay = style {
            // From PageSheet to ApplePay
            hideAnimated(pageSheet: pageSheet) {
                self.showApplePay(vc)
            }
        } else if modules.last is PKPaymentAuthorizationViewController,
                  case .actionSheet = style {
            // From ApplePay to ActionSheet
            dismiss(animated: true) {
                self.presentActionSheetAnimated(vc)
            }
        } else if modules.last is PKPaymentAuthorizationViewController,
                  case .pageSheet = style {
            // From ApplePay to PageSheet
            dismiss(animated: true) {
                self.presentPageSheetAnimated(vc)
            }
        } else if modules.last is PKPaymentAuthorizationViewController,
                  case .modal = style {
            // From ApplePay to Modal
            dismiss(animated: true) {
                self.presentModalAnimated(vc)
            }
        } else {
            // First present. Animation doesn't needed
            switch style {
            case .actionSheet:
                showActionSheet(vc, sender: sender)
            case .modal:
                showModal(vc, sender: sender)
            case .pageSheet:
                showPageSheet(vc, sender: sender)
            case .applePay:
                showApplePay(vc)
            }
        }
    }
    // swiftlint:enable cyclomatic_complexity

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        func getCurrentStyle() -> PresentationStyle {
            let style: PresentationStyle
            if actionSheetTemplate != nil {
                style = .actionSheet
            } else if modalTemplate != nil {
                style = .modal
            } else if pageSheetTemplate != nil {
                style = .pageSheet
            } else {
                style = .modal
            }

            return style
        }

        let style = getCurrentStyle()

        if let vc = modules.last,
           style != getStyle(vc) {
            if let actionSheet = actionSheetTemplate {
                hide(actionSheet: actionSheet)
            } else if let modal = modalTemplate {
                hide(modal: modal)
            } else if let pageSheet = pageSheetTemplate {
                hide(pageSheet: pageSheet)
            }

            switch getStyle(vc) {
            case .actionSheet:
                showActionSheet(vc, sender: self)
            case .pageSheet:
                showPageSheet(vc, sender: self)
            case .modal:
                showModal(vc, sender: self)
            case .applePay:
                break
            }
        }
    }

    func showApplePay(_ vc: UIViewController) {
        modules.append(vc)
        present(vc, animated: true)
    }

    // MARK: - Get presentation style

    func getStyle(_ vc: UIViewController) -> PresentationStyle {
        let style: PresentationStyle
        let vc = vc as? Presentable

        switch traitCollection.horizontalSizeClass {
        case .regular:
            style = vc?.iPadPresentationStyle ?? .pageSheet
        case .compact:
            style = vc?.iPhonePresentationStyle ?? .modal
        case .unspecified:
            style = .modal
        }

        return style
    }

    // MARK: - Present as first screen in stack

    private
    func showActionSheet(_ vc: UIViewController, sender: Any?) {
        let actionSheetTemplate = ActionSheetTemplate()
        actionSheetTemplate.delegate = self

        addChildViewController(actionSheetTemplate)

        actionSheetTemplate.addChildViewController(vc)

        actionSheetTemplate.beginAppearanceTransition(true, animated: false)

        view.addSubview(actionSheetTemplate.view)
        actionSheetTemplate.dummyView.addSubview(vc.view)

        actionSheetTemplate.view.translatesAutoresizingMaskIntoConstraints = false
        vc.view.translatesAutoresizingMaskIntoConstraints = false

        containerConstraints = [
            self.view.leading.constraint(equalTo: actionSheetTemplate.view.leading),
            self.view.trailing.constraint(equalTo: actionSheetTemplate.view.trailing),
            self.view.top.constraint(equalTo: actionSheetTemplate.view.top),
            self.view.bottom.constraint(equalTo: actionSheetTemplate.view.bottom),
        ]

        NSLayoutConstraint.activate(containerConstraints)
        actionSheetTemplate.view.layoutIfNeeded()

        let constraints = [
            actionSheetTemplate.dummyView.leading.constraint(equalTo: vc.view.leading),
            actionSheetTemplate.dummyView.trailing.constraint(equalTo: vc.view.trailing),
            actionSheetTemplate.dummyView.top.constraint(equalTo: vc.view.top),
            actionSheetTemplate.dummyView.bottom.constraint(equalTo: vc.view.bottom),
        ]
        NSLayoutConstraint.activate(constraints)

        vc.didMove(toParentViewController: actionSheetTemplate)

        actionSheetTemplate.endAppearanceTransition()

        modules.append(vc)
        self.actionSheetTemplate = actionSheetTemplate
    }

    private func showModal(_ vc: UIViewController, sender: Any?) {
        let modalTemplate = ModalTemplate()

        addChildViewController(modalTemplate)
        modalTemplate.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modalTemplate.view)

        modalTemplate.addChildViewController(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        modalTemplate.setContentView(vc.view)
        modalTemplate.beginAppearanceTransition(true, animated: true)
        vc.beginAppearanceTransition(true, animated: true)

        let modalTemplateConstraints = [
            view.leading.constraint(equalTo: modalTemplate.view.leading),
            view.trailing.constraint(equalTo: modalTemplate.view.trailing),
            view.top.constraint(equalTo: modalTemplate.view.top),
            view.bottom.constraint(equalTo: modalTemplate.view.bottom),
        ]
        NSLayoutConstraint.activate(modalTemplateConstraints)
        modalTemplate.view.layoutIfNeeded()

        let constraints = [
            modalTemplate.view.leading.constraint(equalTo: vc.view.leading),
            modalTemplate.view.trailing.constraint(equalTo: vc.view.trailing),
            modalTemplate.view.top.constraint(equalTo: vc.view.top),
            modalTemplate.view.bottom.constraint(equalTo: vc.view.bottom),
        ]
        NSLayoutConstraint.activate(constraints)
        modalTemplate.endAppearanceTransition()
        vc.endAppearanceTransition()
        modalTemplate.didMove(toParentViewController: self)
        vc.didMove(toParentViewController: modalTemplate)

        modalTemplate.navigationBar.setItems([vc.navigationItem], animated: false)

        modules.append(vc)
        self.modalTemplate = modalTemplate
    }

    private func showPageSheet(_ vc: UIViewController, sender: Any?) {
        let pageSheet = PageSheetTemplate()
        pageSheet.delegate = self

        addChildViewController(pageSheet)
        pageSheet.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageSheet.view)

        pageSheet.addChildViewController(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        pageSheet.setContentView(vc.view)
        pageSheet.beginAppearanceTransition(true, animated: true)
        vc.beginAppearanceTransition(true, animated: true)

        let modalTemplateConstraints = [
            view.leading.constraint(equalTo: pageSheet.view.leading),
            view.trailing.constraint(equalTo: pageSheet.view.trailing),
            view.top.constraint(equalTo: pageSheet.view.top),
            view.bottom.constraint(equalTo: pageSheet.view.bottom),
        ]
        NSLayoutConstraint.activate(modalTemplateConstraints)
        let hasNavigationBar = (vc as? Presentable)?.hasNavigationBar ?? true
        pageSheet.setNavigationBarHidden(hasNavigationBar == false, animated: false)
        pageSheet.setNavigationItems(modules.map { $0.navigationItem }, animated: false)
        pageSheet.view.layoutIfNeeded()

        pageSheet.endAppearanceTransition()
        vc.endAppearanceTransition()
        pageSheet.didMove(toParentViewController: self)
        vc.didMove(toParentViewController: pageSheet)

        vc.removeKeyboardObservers()

        modules.append(vc)
        self.pageSheetTemplate = pageSheet
    }

    // MARK: - Hide view controller without animation

    private func hide(actionSheet: ActionSheetTemplate) {
        hideContainer(actionSheet)
        self.actionSheetTemplate = nil
    }

    private func hide(modal: ModalTemplate) {
        hideContainer(modal)
        self.modalTemplate = nil
    }

    private func hide(pageSheet: PageSheetTemplate) {
        hideContainer(pageSheet)
        self.pageSheetTemplate = nil
    }

    private func hideContainer(_ vc: UIViewController) {
        vc.willMove(toParentViewController: nil)

        vc.beginAppearanceTransition(false, animated: false)

        containerConstraints = []

        vc.view.removeFromSuperview()
        vc.endAppearanceTransition()

        vc.removeFromParentViewController()
    }

    // MARK: - Hide view controller animated

    private func hideAnimated(actionSheet: ActionSheetTemplate, completion: (() -> Void)? = nil) {
        actionSheet.willMove(toParentViewController: nil)

        actionSheet.beginAppearanceTransition(false, animated: true)

        NSLayoutConstraint.deactivate(containerConstraints)

        let constraints = [
            actionSheet.view.leading.constraint(equalTo: view.leading),
            actionSheet.view.trailing.constraint(equalTo: view.trailing),
            actionSheet.view.height.constraint(equalTo: view.height),
            actionSheet.dummyView.top.constraint(equalTo: view.bottom),
        ]
        NSLayoutConstraint.activate(constraints)

        UIView.animate(withDuration: timeInterval,
                       animations: {
                           self.view.layoutIfNeeded()
                       },
                       completion: { _ in
                           actionSheet.endAppearanceTransition()
                           actionSheet.view.removeFromSuperview()
                           actionSheet.removeFromParentViewController()
                           self.actionSheetTemplate = nil
                           completion?()
                       })
    }

    private func hideAnimated(pageSheet: PageSheetTemplate, completion: (() -> Void)? = nil) {
        pageSheet.willMove(toParentViewController: nil)
        pageSheet.beginAppearanceTransition(false, animated: true)
        NSLayoutConstraint.deactivate(containerConstraints)

        let dismissConstraint = [
            pageSheet.view.leading.constraint(equalTo: view.leading),
            pageSheet.view.trailing.constraint(equalTo: view.trailing),
            pageSheet.view.height.constraint(equalTo: view.height),
            pageSheet.dummyView.top.constraint(equalTo: view.bottom),
        ]
        NSLayoutConstraint.activate(dismissConstraint)

        UIView.animate(withDuration: timeInterval,
                       animations: {
                           self.view.layoutIfNeeded()
                       },
                       completion: { _ in
                           pageSheet.endAppearanceTransition()
                           pageSheet.view.removeFromSuperview()
                           pageSheet.removeFromParentViewController()
                           self.pageSheetTemplate = nil
                           completion?()
                       })
    }

    // MARK: - Present view controller animated

    private func presentModalAnimated(_ vc: UIViewController, completion: (() -> Void)? = nil) {
        let modalTemplate = ModalTemplate()

        modules.append(vc)

        addChildViewController(modalTemplate)
        modalTemplate.beginAppearanceTransition(true, animated: true)
        modalTemplate.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(modalTemplate.view)

        modalTemplate.addChildViewController(vc)
        vc.beginAppearanceTransition(true, animated: true)
        modalTemplate.setContentView(vc.view)

        let startConstraints = [
            modalTemplate.view.leading.constraint(equalTo: view.leading),
            modalTemplate.view.top.constraint(equalTo: view.bottom),
            modalTemplate.view.width.constraint(equalTo: view.width),
            modalTemplate.view.height.constraint(equalTo: view.height),
        ]

        NSLayoutConstraint.activate(startConstraints)
        view.layoutIfNeeded()

        let endConstraints = [
            modalTemplate.view.leading.constraint(equalTo: view.leading),
            modalTemplate.view.trailing.constraint(equalTo: view.trailing),
            modalTemplate.view.top.constraint(equalTo: view.top),
            modalTemplate.view.bottom.constraint(equalTo: view.bottom),
        ]

        NSLayoutConstraint.deactivate(startConstraints)
        NSLayoutConstraint.activate(endConstraints)

        modalTemplate.setNavigationItems(modules.map { $0.navigationItem }, animated: false)

        UIView.animate(withDuration: timeInterval,
                       animations: {
                           self.view.layoutIfNeeded()
                       },
                       completion: { _ in
                           modalTemplate.endAppearanceTransition()
                           vc.endAppearanceTransition()
                           modalTemplate.didMove(toParentViewController: self)
                           vc.didMove(toParentViewController: modalTemplate)
                           self.modalTemplate = modalTemplate
                           completion?()
                       })
    }

    private func presentPageSheetAnimated(_ vc: UIViewController, completion: (() -> Void)? = nil) {
        let pageSheet = PageSheetTemplate()
        pageSheet.delegate = self

        addChildViewController(pageSheet)
        pageSheet.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pageSheet.view)

        pageSheet.addChildViewController(vc)
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        pageSheet.setContentView(vc.view)
        pageSheet.beginAppearanceTransition(true, animated: true)
        vc.beginAppearanceTransition(true, animated: true)

        let startConstraints = [
            pageSheet.view.leading.constraint(equalTo: view.leading),
            pageSheet.view.top.constraint(equalTo: view.bottom),
            pageSheet.view.width.constraint(equalTo: view.width),
            pageSheet.view.height.constraint(equalTo: view.height),
        ]

        NSLayoutConstraint.activate(startConstraints)
        view.layoutIfNeeded()

        let endConstraints = [
            pageSheet.view.leading.constraint(equalTo: view.leading),
            pageSheet.view.trailing.constraint(equalTo: view.trailing),
            pageSheet.view.top.constraint(equalTo: view.top),
            pageSheet.view.bottom.constraint(equalTo: view.bottom),
        ]

        NSLayoutConstraint.deactivate(startConstraints)
        NSLayoutConstraint.activate(endConstraints)

        let hasNavigationBar = (vc as? Presentable)?.hasNavigationBar ?? true
        pageSheet.setNavigationBarHidden(hasNavigationBar == false, animated: false)
        pageSheet.setNavigationItems(modules.map { $0.navigationItem }, animated: false)

        UIView.animate(withDuration: timeInterval,
                       animations: {
                           self.view.layoutIfNeeded()
                       },
                       completion: { _ in
                           pageSheet.endAppearanceTransition()
                           vc.endAppearanceTransition()
                           pageSheet.didMove(toParentViewController: self)
                           vc.didMove(toParentViewController: pageSheet)
                           completion?()
                       })

        vc.removeKeyboardObservers()
        modules.append(vc)
        self.pageSheetTemplate = pageSheet
    }

    private func presentActionSheetAnimated(_ vc: UIViewController, completion: (() -> Void)? = nil) {
        let actionSheetTemplate = ActionSheetTemplate()
        actionSheetTemplate.delegate = self

        addChildViewController(actionSheetTemplate)
        actionSheetTemplate.addChildViewController(vc)
        actionSheetTemplate.beginAppearanceTransition(true, animated: false)

        view.addSubview(actionSheetTemplate.view)
        actionSheetTemplate.dummyView.addSubview(vc.view)

        actionSheetTemplate.view.translatesAutoresizingMaskIntoConstraints = false
        vc.view.translatesAutoresizingMaskIntoConstraints = false

        let dummyViewConstraints = [
            actionSheetTemplate.dummyView.leading.constraint(equalTo: vc.view.leading),
            actionSheetTemplate.dummyView.trailing.constraint(equalTo: vc.view.trailing),
            actionSheetTemplate.dummyView.top.constraint(equalTo: vc.view.top),
            actionSheetTemplate.dummyView.bottom.constraint(equalTo: vc.view.bottom),
        ]

        NSLayoutConstraint.activate(dummyViewConstraints)

        let startConstraints = [
            actionSheetTemplate.view.leading.constraint(equalTo: view.leading),
            actionSheetTemplate.view.top.constraint(equalTo: view.bottom),
            actionSheetTemplate.view.width.constraint(equalTo: view.width),
            actionSheetTemplate.view.height.constraint(equalTo: view.height),
        ]

        NSLayoutConstraint.activate(startConstraints)
        view.layoutIfNeeded()

        let endConstraints = [
            actionSheetTemplate.view.leading.constraint(equalTo: view.leading),
            actionSheetTemplate.view.trailing.constraint(equalTo: view.trailing),
            actionSheetTemplate.view.top.constraint(equalTo: view.top),
            actionSheetTemplate.view.bottom.constraint(equalTo: view.bottom),
        ]

        NSLayoutConstraint.deactivate(startConstraints)
        NSLayoutConstraint.activate(endConstraints)

        UIView.animate(withDuration: timeInterval,
                       animations: {
                           self.view.layoutIfNeeded()
                       },
                       completion: { _ in
                           actionSheetTemplate.endAppearanceTransition()
                           actionSheetTemplate.didMove(toParentViewController: self)
                           completion?()
                       })

        modules.append(vc)
        self.actionSheetTemplate = actionSheetTemplate
    }

    // MARK: - Push without change container

    private func pushActionSheet(_ actionSheetTemplate: ActionSheetTemplate,
                                 previous pvc: UIViewController,
                                 next nvc: UIViewController,
                                 sender: Any?) {
        pvc.willMove(toParentViewController: nil)
        actionSheetTemplate.addChildViewController(nvc)

        nvc.view.translatesAutoresizingMaskIntoConstraints = false

        actionSheetTemplate.dummyView.addSubview(nvc.view)

        nvc.beginAppearanceTransition(true, animated: true)
        pvc.beginAppearanceTransition(false, animated: true)

        let startConstraints = [
            nvc.view.leading.constraint(equalTo: pvc.view.trailing),
            nvc.view.top.constraint(equalTo: pvc.view.top),
            nvc.view.width.constraint(equalTo: pvc.view.width),
            nvc.view.height.constraint(equalTo: pvc.view.height),
        ]

        NSLayoutConstraint.activate(startConstraints)
        actionSheetTemplate.dummyView.setNeedsLayout()
        actionSheetTemplate.dummyView.layoutIfNeeded()

        let endConstraints = [
            actionSheetTemplate.dummyView.leading.constraint(equalTo: nvc.view.leading),
            actionSheetTemplate.dummyView.trailing.constraint(equalTo: nvc.view.trailing),
            actionSheetTemplate.dummyView.top.constraint(equalTo: nvc.view.top),
            actionSheetTemplate.dummyView.bottom.constraint(equalTo: nvc.view.bottom),
        ]

        NSLayoutConstraint.deactivate(startConstraints)
        NSLayoutConstraint.activate(endConstraints)

        UIView.animate(withDuration: timeInterval,
                       animations: {
                           actionSheetTemplate.dummyView.layoutIfNeeded()
                       },
                       completion: { _ in
                           pvc.view.removeFromSuperview()
                           pvc.endAppearanceTransition()
                           UIView.animate(withDuration: timeInterval,
                                          animations: {
                                              actionSheetTemplate.view.layoutIfNeeded()
                                          },
                                          completion: { _ in
                                              nvc.endAppearanceTransition()
                                          })

                           pvc.removeFromParentViewController()
                           nvc.didMove(toParentViewController: actionSheetTemplate)

                           self.modules.append(nvc)
                       })
    }

    private func pushPageSheet(_ pageSheet: PageSheetTemplate,
                               previous pvc: UIViewController,
                               next nvc: UIViewController,
                               sender: Any?) {
        pvc.willMove(toParentViewController: nil)
        pageSheet.addChildViewController(nvc)

        nvc.view.translatesAutoresizingMaskIntoConstraints = false

        pageSheet.dummyView.addSubview(nvc.view)

        nvc.removeKeyboardObservers()

        let startConstraints = [
            nvc.view.leading.constraint(equalTo: pvc.view.trailing),
            nvc.view.top.constraint(equalTo: pvc.view.top),
            nvc.view.width.constraint(equalTo: pvc.view.width),
            nvc.view.height.constraint(equalTo: pvc.view.height),
        ]

        NSLayoutConstraint.activate(startConstraints)
        pageSheet.dummyView.setNeedsLayout()
        pageSheet.dummyView.layoutIfNeeded()

        pvc.beginAppearanceTransition(false, animated: true)
        nvc.beginAppearanceTransition(true, animated: true)

        NSLayoutConstraint.deactivate(startConstraints)
        pageSheet.setContentView(nvc.view)

        let hasNavigationBar = (nvc as? Presentable)?.hasNavigationBar ?? true
        pageSheet.pushNavigationItem(nvc.navigationItem, animated: false)
        pageSheet.setNavigationBarHidden(hasNavigationBar == false, animated: false)

        UIView.animate(withDuration: timeInterval,
                       animations: {
                           pageSheet.dummyView.layoutIfNeeded()
                       },
                       completion: { _ in
                           pvc.view.removeFromSuperview()
                           UIView.animate(withDuration: timeInterval,
                                          animations: {
                                              pageSheet.view.layoutIfNeeded()
                                          },
                                          completion: { _ in
                                              nvc.endAppearanceTransition()
                                              nvc.didMove(toParentViewController: pageSheet)
                                          })

                           pvc.endAppearanceTransition()
                           pvc.removeFromParentViewController()

                           self.modules.append(nvc)
                       })
    }

    private func pushModal(_ modal: ModalTemplate,
                           previous pvc: UIViewController,
                           next nvc: UIViewController,
                           sender: Any?) {
        pvc.willMove(toParentViewController: nil)
        modal.addChildViewController(nvc)

        nvc.view.translatesAutoresizingMaskIntoConstraints = false

        modal.view.insertSubview(nvc.view, belowSubview: modal.navigationBar)

        nvc.removeKeyboardObservers()

        let startConstraints = [
            nvc.view.leading.constraint(equalTo: pvc.view.trailing),
            nvc.view.top.constraint(equalTo: pvc.view.top),
            nvc.view.width.constraint(equalTo: pvc.view.width),
            nvc.view.height.constraint(equalTo: pvc.view.height),
        ]

        NSLayoutConstraint.activate(startConstraints)
        modal.view.setNeedsLayout()
        modal.view.layoutIfNeeded()

        pvc.beginAppearanceTransition(false, animated: true)
        nvc.beginAppearanceTransition(true, animated: true)

        NSLayoutConstraint.deactivate(startConstraints)
        modal.setContentView(nvc.view)

        let hasNavigationBar = (nvc as? Presentable)?.hasNavigationBar ?? true
        modal.pushNavigationItem(nvc.navigationItem, animated: false)
        modal.setNavigationBarHidden(hasNavigationBar == false, animated: false)

        UIView.animate(withDuration: timeInterval,
                       animations: {
                           modal.view.layoutIfNeeded()
                       },
                       completion: { _ in
                           pvc.view.removeFromSuperview()
                           UIView.animate(withDuration: timeInterval,
                                          animations: {
                                              modal.view.layoutIfNeeded()
                                          },
                                          completion: { _ in
                                              nvc.endAppearanceTransition()
                                              nvc.didMove(toParentViewController: modal)
                                          })

                           pvc.endAppearanceTransition()
                           pvc.removeFromParentViewController()

                           self.modules.append(nvc)
                       })
    }
}

extension TokenizationViewController: ActionSheetTemplateDelegate {
    func actionSheetTemplateDidFinish(_ template: ActionSheetTemplate) {
        output?.closeDidPress()
    }
}

extension TokenizationViewController: PageSheetTemplateDelegate {
    func pageSheetTemplateDidFinish(_ template: PageSheetTemplate) {
        output?.closeDidPress()
    }
}

// MARK: - TokenizationModuleInput

extension TokenizationViewController: TokenizationModuleInput {
    func start3dsProcess(requestUrl: String, redirectUrl: String) {
        output.start3dsProcess(requestUrl: requestUrl, redirectUrl: redirectUrl)
    }
}
