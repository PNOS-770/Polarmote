use std::time::{Duration, Instant};

#[derive(Debug, Clone)]
pub struct AdaptiveSchedulerConfig {
    pub min_parallel: usize,
    pub max_parallel: usize,
    pub cooldown: Duration,
    pub min_success_window: usize,
}

impl Default for AdaptiveSchedulerConfig {
    fn default() -> Self {
        Self {
            min_parallel: 1,
            max_parallel: 8,
            cooldown: Duration::from_secs(2),
            min_success_window: 3,
        }
    }
}

#[derive(Debug, Clone)]
pub struct AdaptiveFeedback {
    pub success: bool,
    pub throughput_bps: Option<u64>,
    #[allow(dead_code)]
    pub transient_error: bool,
}

pub struct AdaptiveController {
    config: AdaptiveSchedulerConfig,
    current_parallel: usize,
    last_adjust_at: Instant,
    success_streak: usize,
    failure_streak: usize,
    last_throughput_bps: u64,
}

impl AdaptiveController {
    pub fn new(config: AdaptiveSchedulerConfig) -> Self {
        let min_parallel = config.min_parallel.max(1);
        Self {
            current_parallel: min_parallel,
            last_adjust_at: Instant::now(),
            success_streak: 0,
            failure_streak: 0,
            last_throughput_bps: 0,
            config,
        }
    }

    pub fn current_parallelism(&self) -> usize {
        self.current_parallel
    }

    pub fn update(&mut self, feedback: AdaptiveFeedback) -> usize {
        if feedback.success {
            self.success_streak = self.success_streak.saturating_add(1);
            self.failure_streak = 0;
        } else {
            self.failure_streak = self.failure_streak.saturating_add(1);
            self.success_streak = 0;
        }

        if let Some(throughput) = feedback.throughput_bps {
            self.last_throughput_bps = throughput;
        }

        if self.last_adjust_at.elapsed() < self.config.cooldown {
            return self.current_parallel;
        }

        if !feedback.success {
            // Fail fast on repeated errors.
            if self.failure_streak >= 1 {
                self.current_parallel = self
                    .current_parallel
                    .saturating_sub(1)
                    .max(self.config.min_parallel);
                self.last_adjust_at = Instant::now();
            }
            return self.current_parallel;
        }

        if self.success_streak >= self.config.min_success_window
            && self.current_parallel < self.config.max_parallel
        {
            self.current_parallel += 1;
            self.success_streak = 0;
            self.last_adjust_at = Instant::now();
        }

        self.current_parallel
    }

    pub fn note_queue_pressure(&mut self, queued: usize, running: usize) {
        if queued > running.saturating_mul(3)
            && self.current_parallel < self.config.max_parallel
            && self.last_adjust_at.elapsed() >= self.config.cooldown
        {
            self.current_parallel += 1;
            self.last_adjust_at = Instant::now();
        }
    }

    #[allow(dead_code)]
    pub fn last_throughput_bps(&self) -> u64 {
        self.last_throughput_bps
    }
}
