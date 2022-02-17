package com.daniyaalkhan.imgmap;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

public class Chart {

    public int id;

    public Chart(int id, String name) {
        this.id = id;
        this.name = name;
    }

    public String name;
    public Bitmap chartBitmap;
    public double[][] coords1, coords2;

    public Chart() {}

    public int getId() {
        return id;
    }

    public void setId(int id) {
        this.id = id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }



    public void setBitmap(byte[] chartBytes) {
        this.chartBitmap = BitmapFactory.decodeByteArray(chartBytes, 0, chartBytes.length);
    }

    public double[][] getCoords1() {
        return coords1;
    }

    public void setCoords1(double[][] coords1) {
        this.coords1 = coords1;
    }

    public double[][] getCoords2() {
        return coords2;
    }

    public void setCoords2(double[][] coords2) {
        this.coords2 = coords2;
    }
}
