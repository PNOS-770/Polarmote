use std::time::Instant;

pub struct SpeedSampler {
    started_at: Instant,
    last_sample_at: Instant,
    last_bytes: u64,
}

impl SpeedSampler {
    pub fn new() -> Self {
        let now = Instant::now();
        Self {
            started_at: now,
            last_sample_at: now,
            last_bytes: 0,
        }
    }

    pub fn sample(&mut self, bytes: u64) -> Option<u64> {
        let elapsed = self.last_sample_at.elapsed();
        if elapsed.as_millis() < 250 {
            return None;
        }
        let delta_bytes = bytes.saturating_sub(self.last_bytes);
        let seconds = elapsed.as_secs_f64();
        self.last_sample_at = Instant::now();
        self.last_bytes = bytes;
        if seconds <= 0.0 {
            return None;
        }
        Some((delta_bytes as f64 / seconds) as u64)
    }

    #[allow(dead_code)]
    pub fn total_elapsed_ms(&self) -> u64 {
        self.started_at.elapsed().as_millis() as u64
    }
}
