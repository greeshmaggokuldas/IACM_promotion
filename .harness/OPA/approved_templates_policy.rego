package harness.pipeline.template_enforcement

import future.keywords.contains
import future.keywords.if
import future.keywords.in

# =============================================================================
# DENY: stage itself is inline (not a template reference)
# =============================================================================
deny contains msg if {
    some i
    stage := input.pipeline.stages[i].stage
    not stage.template.templateRef
    msg := sprintf(
        "Pipeline blocked: stage '%s' is inline — stages must use a template.",
        [stage.identifier]
    )
}

deny contains msg if {
    some i, j
    stage := input.pipeline.stages[i].parallel[j].stage
    not stage.template.templateRef
    msg := sprintf(
        "Pipeline blocked: parallel stage '%s' is inline — stages must use a template.",
        [stage.identifier]
    )
}

# =============================================================================
# DENY: step is inline — BUT ONLY inside stages that are NOT template-based
# Steps inside a template stage are owned by the template, skip them
# =============================================================================
deny contains msg if {
    some i, j
    stage := input.pipeline.stages[i].stage
    not stage.template.templateRef          # ← stage is inline, so check its steps
    step := stage.spec.execution.steps[j].step
    not step.template.templateRef
    msg := sprintf(
        "Pipeline blocked: step '%s' in stage '%s' is inline — use a template.",
        [step.identifier, stage.identifier]
    )
}

deny contains msg if {
    some i, j, k
    stage := input.pipeline.stages[i].parallel[j].stage
    not stage.template.templateRef          # ← same guard for parallel stages
    step := stage.spec.execution.steps[k].step
    not step.template.templateRef
    msg := sprintf(
        "Pipeline blocked: step '%s' in parallel stage '%s' is inline — use a template.",
        [step.identifier, stage.identifier]
    )
}

# =============================================================================
# DENY: stepGroup inline — only in non-template stages
# =============================================================================
deny contains msg if {
    some i, j
    stage := input.pipeline.stages[i].stage
    not stage.template.templateRef
    sg := stage.spec.execution.steps[j].stepGroup
    not sg.template.templateRef
    msg := sprintf(
        "Pipeline blocked: stepGroup '%s' in stage '%s' is inline — use a template.",
        [sg.identifier, stage.identifier]
    )
}