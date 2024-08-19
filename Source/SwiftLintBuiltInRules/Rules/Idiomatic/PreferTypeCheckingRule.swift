import SwiftSyntax
import SwiftSyntaxBuilder

@SwiftSyntaxRule(explicitRewriter: true)
struct PreferTypeCheckingRule: Rule {
    var configuration = SeverityConfiguration<Self>(.warning)

    static let description = RuleDescription(
        identifier: "prefer_type_checking",
        name: "Prefer Type Checking",
        description: "Prefer `a is X` to `a as? X != nil`",
        kind: .idiomatic,
        nonTriggeringExamples: [
            Example("let foo = bar as? Foo"),
            Example("bar is Foo"),
            Example("""
            if foo is Bar {
                doSomeThing()
            }
            """),
            Example("""
            if let bar = foo as? Bar {
                foo.run()
            }
            """),
        ],
        triggeringExamples: [
            Example("bar ↓as? Foo != nil"),
            Example("""
            if foo ↓as? Bar != nil {
                doSomeThing()
            }
            """),
        ],
        corrections: [
            Example("bar ↓as? Foo != nil"): Example("bar is Foo"),
            Example("""
            if foo ↓as? Bar != nil {
                doSomeThing()
            }
            """): Example("""
            if foo is Bar {
                doSomeThing()
            }
            """),
        ]
    )
}

private extension PreferTypeCheckingRule {
    final class Visitor: ViolationsSyntaxVisitor<ConfigurationType> {
        override func visitPost(_ node: UnresolvedAsExprSyntax) {
            if node.asWithQuestionMarkExprIsBeingComparedToNotNil() {
                violations.append(node.asKeyword.positionAfterSkippingLeadingTrivia)
            }
        }
    }

    final class Rewriter: ViolationsSyntaxRewriter<ConfigurationType> {
        override func visit(_ node: ExprListSyntax) -> ExprListSyntax {
            guard
                node.unresolvedAsExprIsBeingComparedToNotNil,
                let unresolvedAsExpr = node.dropFirst().first,
                let indexUnresolvedAsExpr = node.index(of: unresolvedAsExpr),
                let typeExpr = node.dropFirst(2).first
            else {
                return super.visit(node)
            }
            correctionPositions.append(unresolvedAsExpr.positionAfterSkippingLeadingTrivia)
            let elements = node
                .with(
                    \.[indexUnresolvedAsExpr],
                    "is \(typeExpr.trimmed)"
                )
                .dropLast(3)
            let newNode = ExprListSyntax(elements)
                .with(\.leadingTrivia, node.leadingTrivia)
                .with(\.trailingTrivia, node.trailingTrivia)
            return super.visit(newNode)
        }
    }
}

private extension ExprSyntaxProtocol {
    func asWithQuestionMarkExprIsBeingComparedToNotNil() -> Bool {
        guard let node = self.as(UnresolvedAsExprSyntax.self),
              let parent = parent?.as(ExprListSyntax.self),
              let last = parent.last, last.is(NilLiteralExprSyntax.self) else {
            return false
        }
        return node.questionOrExclamationMark?.tokenKind == .postfixQuestionMark && parent.dropLast().last?.as(BinaryOperatorExprSyntax.self)?.operator.tokenKind == .binaryOperator("!=")
    }
}

private extension ExprListSyntax {
    var unresolvedAsExprIsBeingComparedToNotNil: Bool {
        guard
            let node = dropFirst().first?.as(UnresolvedAsExprSyntax.self),
            node.asWithQuestionMarkExprIsBeingComparedToNotNil()
        else {
            return false
        }

        return true
    }
}
