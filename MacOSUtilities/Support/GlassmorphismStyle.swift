import SwiftUI

enum GlassmorphismStyle {
    static let panelCornerRadius: CGFloat = 18
    static let sectionCornerRadius: CGFloat = 12
    static let rowCornerRadius: CGFloat = 10
    static let iconCornerRadius: CGFloat = 8
}

struct GlassSurfaceModifier: ViewModifier {
    var cornerRadius: CGFloat
    var material: Material
    var tint: Color
    var isInteractive: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .overlay(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.20),
                                        tint.opacity(0.08),
                                        Color.black.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.softLight)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.38),
                                tint.opacity(0.24),
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            }
            .shadow(color: Color.black.opacity(isInteractive ? 0.16 : 0.10), radius: isInteractive ? 14 : 9, x: 0, y: isInteractive ? 8 : 5)
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var size: CGFloat = 30
    var isProminent = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary.opacity(isEnabled ? 1 : 0.55))
            .frame(width: size, height: size)
            .background {
                Circle()
                    .fill(.thinMaterial)
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(isProminent ? 0.58 : 0.20),
                                        Color.white.opacity(configuration.isPressed ? 0.28 : 0.14),
                                        Color.black.opacity(0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(isProminent ? .normal : .softLight)
                    }
            }
            .overlay {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.52),
                                tint.opacity(isProminent ? 0.56 : 0.30),
                                Color.black.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: tint.opacity(isProminent ? 0.35 : 0.18), radius: configuration.isPressed ? 4 : 10, x: 0, y: configuration.isPressed ? 2 : 6)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct GlassPillButtonStyle: ButtonStyle {
    var tint: Color = .accentColor
    var isProminent = false
    var horizontalPadding: CGFloat = 12

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isProminent ? Color.white : Color.primary.opacity(isEnabled ? 1 : 0.55))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(isProminent ? 0.58 : 0.18),
                                        Color.white.opacity(configuration.isPressed ? 0.26 : 0.12),
                                        Color.black.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(isProminent ? .normal : .softLight)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.46),
                                tint.opacity(isProminent ? 0.62 : 0.32),
                                Color.black.opacity(0.20)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            }
            .shadow(color: tint.opacity(isProminent ? 0.30 : 0.14), radius: configuration.isPressed ? 4 : 12, x: 0, y: configuration.isPressed ? 2 : 7)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct AmbientGlassBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor).opacity(0.72),
                    Color(nsColor: .controlBackgroundColor).opacity(0.48),
                    Color.accentColor.opacity(0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.accentColor.opacity(0.18))
                .blur(radius: 34)
                .frame(width: 170, height: 170)
                .offset(x: -160, y: -130)

            Circle()
                .fill(Color.orange.opacity(0.14))
                .blur(radius: 38)
                .frame(width: 180, height: 180)
                .offset(x: 170, y: 150)
        }
    }
}

extension View {
    func glassSurface(
        cornerRadius: CGFloat = GlassmorphismStyle.sectionCornerRadius,
        material: Material = .thinMaterial,
        tint: Color = .accentColor,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            GlassSurfaceModifier(
                cornerRadius: cornerRadius,
                material: material,
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }

    func glassIconTile(
        cornerRadius: CGFloat = GlassmorphismStyle.iconCornerRadius,
        tint: Color = .accentColor
    ) -> some View {
        frame(width: 34, height: 34)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        LinearGradient(
                            colors: [
                                tint.opacity(0.34),
                                Color.white.opacity(0.14)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6)
            }
    }

    func glassInputField(
        cornerRadius: CGFloat = GlassmorphismStyle.iconCornerRadius,
        tint: Color = .accentColor
    ) -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.14),
                                        tint.opacity(0.08),
                                        Color.black.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.softLight)
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.7)
            }
    }
}
