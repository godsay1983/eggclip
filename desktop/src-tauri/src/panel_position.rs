const PANEL_GAP: f64 = 8.0;
const WORK_AREA_MARGIN: f64 = 8.0;
const CORNER_MARGIN: f64 = 16.0;

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Rect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Size {
    pub width: f64,
    pub height: f64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub(crate) struct Point {
    pub x: f64,
    pub y: f64,
}

impl Rect {
    pub(crate) fn center(self) -> Point {
        Point {
            x: self.x + self.width / 2.0,
            y: self.y + self.height / 2.0,
        }
    }

    fn right(self) -> f64 {
        self.x + self.width
    }

    fn bottom(self) -> f64 {
        self.y + self.height
    }
}

#[derive(Clone, Copy)]
enum ScreenEdge {
    Top,
    Right,
    Bottom,
    Left,
}

pub(crate) fn near_tray(anchor: Rect, work_area: Rect, panel: Size, scale_factor: f64) -> Point {
    let gap = PANEL_GAP * scale_factor;
    let margin = WORK_AREA_MARGIN * scale_factor;
    let candidate = match nearest_edge(anchor.center(), work_area) {
        ScreenEdge::Top => Point {
            x: anchor.x,
            y: anchor.bottom() + gap,
        },
        ScreenEdge::Right => Point {
            x: anchor.x - panel.width - gap,
            y: anchor.center().y - panel.height / 2.0,
        },
        ScreenEdge::Bottom => Point {
            x: anchor.right() - panel.width,
            y: anchor.y - panel.height - gap,
        },
        ScreenEdge::Left => Point {
            x: anchor.right() + gap,
            y: anchor.center().y - panel.height / 2.0,
        },
    };

    clamp_to_work_area(candidate, work_area, panel, margin)
}

pub(crate) fn at_bottom_right(work_area: Rect, panel: Size, scale_factor: f64) -> Point {
    let corner_margin = CORNER_MARGIN * scale_factor;
    clamp_to_work_area(
        Point {
            x: work_area.right() - panel.width - corner_margin,
            y: work_area.bottom() - panel.height - corner_margin,
        },
        work_area,
        panel,
        WORK_AREA_MARGIN * scale_factor,
    )
}

fn nearest_edge(point: Point, work_area: Rect) -> ScreenEdge {
    [
        ((point.y - work_area.y).abs(), ScreenEdge::Top),
        ((work_area.right() - point.x).abs(), ScreenEdge::Right),
        ((work_area.bottom() - point.y).abs(), ScreenEdge::Bottom),
        ((point.x - work_area.x).abs(), ScreenEdge::Left),
    ]
    .into_iter()
    .min_by(|left, right| left.0.total_cmp(&right.0))
    .map(|(_, edge)| edge)
    .unwrap_or(ScreenEdge::Bottom)
}

fn clamp_to_work_area(point: Point, work_area: Rect, panel: Size, margin: f64) -> Point {
    let min_x = work_area.x + margin;
    let min_y = work_area.y + margin;
    let max_x = (work_area.right() - panel.width - margin).max(min_x);
    let max_y = (work_area.bottom() - panel.height - margin).max(min_y);

    Point {
        x: point.x.clamp(min_x, max_x),
        y: point.y.clamp(min_y, max_y),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const PANEL: Size = Size {
        width: 440.0,
        height: 680.0,
    };

    #[test]
    fn opens_above_a_bottom_taskbar_tray() {
        let position = near_tray(
            Rect {
                x: 1880.0,
                y: 1040.0,
                width: 24.0,
                height: 24.0,
            },
            Rect {
                x: 0.0,
                y: 0.0,
                width: 1920.0,
                height: 1040.0,
            },
            PANEL,
            1.0,
        );

        assert_eq!(
            position,
            Point {
                x: 1464.0,
                y: 352.0
            }
        );
    }

    #[test]
    fn keeps_an_oversized_panel_inside_the_work_area() {
        let position = at_bottom_right(
            Rect {
                x: 100.0,
                y: 50.0,
                width: 300.0,
                height: 400.0,
            },
            PANEL,
            1.0,
        );

        assert_eq!(position, Point { x: 108.0, y: 58.0 });
    }
}
