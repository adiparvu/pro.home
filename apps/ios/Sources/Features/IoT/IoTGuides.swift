import SwiftUI

// MARK: - IoT & integrations guides
//
// The GuideTopic content behind every info button on the IoT hub and the
// custom-integrations page. Written to be followed by a child: what the
// thing is, numbered steps, real examples, and the honest requirements.

enum IoTGuides {

    static var controllers: GuideTopic {
        GuideTopic(
            icon: "cpu.fill",
            title: "iotg_ctrl_title",
            intro: "iotg_ctrl_intro",
            sections: [
                GuideSection(icon: "questionmark.circle.fill",
                             title: "iotg_ctrl_what_t",
                             body: "iotg_ctrl_what_b",
                             examples: ["iotg_ctrl_what_e1", "iotg_ctrl_what_e2", "iotg_ctrl_what_e3"]),
                GuideSection(icon: "plus.circle.fill",
                             title: "iotg_ctrl_add_t",
                             steps: ["iotg_ctrl_add_s1", "iotg_ctrl_add_s2",
                                     "iotg_ctrl_add_s3", "iotg_ctrl_add_s4"],
                             note: "iotg_ctrl_add_n"),
                GuideSection(icon: "arrow.clockwise.circle.fill",
                             title: "iotg_ctrl_poll_t",
                             body: "iotg_ctrl_poll_b"),
                GuideSection(icon: "lock.circle.fill",
                             title: "iotg_ctrl_sec_t",
                             body: "iotg_ctrl_sec_b")
            ],
            accent: .brandPrimaryBlue
        )
    }

    static var sensors: GuideTopic {
        GuideTopic(
            icon: "sensor.tag.radiowaves.forward.fill",
            title: "iotg_sens_title",
            intro: "iotg_sens_intro",
            sections: [
                GuideSection(icon: "questionmark.circle.fill",
                             title: "iotg_sens_what_t",
                             body: "iotg_sens_what_b",
                             examples: ["iotg_sens_what_e1", "iotg_sens_what_e2", "iotg_sens_what_e3"]),
                GuideSection(icon: "wand.and.rays",
                             title: "iotg_sens_auto_t",
                             steps: ["iotg_sens_auto_s1", "iotg_sens_auto_s2", "iotg_sens_auto_s3"]),
                GuideSection(icon: "plus.circle.fill",
                             title: "iotg_sens_man_t",
                             steps: ["iotg_sens_man_s1", "iotg_sens_man_s2", "iotg_sens_man_s3"]),
                GuideSection(icon: "bolt.circle.fill",
                             title: "iotg_sens_energy_t",
                             body: "iotg_sens_energy_b",
                             note: "iotg_sens_energy_n")
            ],
            accent: .brandSuccess
        )
    }

    static var automations: GuideTopic {
        GuideTopic(
            icon: "bolt.badge.automatic.fill",
            title: "iotg_auto_title",
            intro: "iotg_auto_intro",
            sections: [
                GuideSection(icon: "questionmark.circle.fill",
                             title: "iotg_auto_what_t",
                             body: "iotg_auto_what_b",
                             examples: ["iotg_auto_what_e1", "iotg_auto_what_e2", "iotg_auto_what_e3"]),
                GuideSection(icon: "plus.circle.fill",
                             title: "iotg_auto_make_t",
                             steps: ["iotg_auto_make_s1", "iotg_auto_make_s2", "iotg_auto_make_s3",
                                     "iotg_auto_make_s4", "iotg_auto_make_s5"]),
                GuideSection(icon: "square.grid.2x2.fill",
                             title: "iotg_auto_act_t",
                             body: "iotg_auto_act_b",
                             examples: ["iotg_auto_act_e1", "iotg_auto_act_e2",
                                        "iotg_auto_act_e3", "iotg_auto_act_e4"]),
                GuideSection(icon: "iphone.gen3",
                             title: "iotg_auto_phone_t",
                             body: "iotg_auto_phone_b",
                             steps: ["iotg_auto_phone_s1", "iotg_auto_phone_s2", "iotg_auto_phone_s3"],
                             note: "iotg_auto_phone_n")
            ],
            accent: .brandPurple
        )
    }

    static var integrations: GuideTopic {
        GuideTopic(
            icon: "puzzlepiece.extension.fill",
            title: "iotg_intg_title",
            intro: "iotg_intg_intro",
            sections: [
                GuideSection(icon: "questionmark.circle.fill",
                             title: "iotg_intg_what_t",
                             body: "iotg_intg_what_b",
                             examples: ["iotg_intg_what_e1", "iotg_intg_what_e2", "iotg_intg_what_e3"]),
                GuideSection(icon: "plus.circle.fill",
                             title: "iotg_intg_add_t",
                             steps: ["iotg_intg_add_s1", "iotg_intg_add_s2",
                                     "iotg_intg_add_s3", "iotg_intg_add_s4"]),
                GuideSection(icon: "paperplane.circle.fill",
                             title: "iotg_intg_send_t",
                             body: "iotg_intg_send_b",
                             note: "iotg_intg_send_n"),
                GuideSection(icon: "lock.circle.fill",
                             title: "iotg_intg_sec_t",
                             steps: ["iotg_intg_sec_s1", "iotg_intg_sec_s2", "iotg_intg_sec_s3"])
            ],
            accent: .brandIndigo
        )
    }
}
