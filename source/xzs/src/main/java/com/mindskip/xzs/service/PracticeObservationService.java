package com.mindskip.xzs.service;

import com.mindskip.xzs.viewmodel.admin.practice.PracticeObservationRequestVM;
import com.mindskip.xzs.viewmodel.admin.practice.PracticeObservationResponseVM;

import java.time.LocalDate;

public interface PracticeObservationService {

    PracticeObservationResponseVM observe(PracticeObservationRequestVM request, LocalDate today);
}
