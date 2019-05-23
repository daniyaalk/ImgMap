package com.daniyaalkhan.imgmap;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.graphics.Bitmap;
import android.graphics.PointF;
import android.net.Uri;
import android.provider.MediaStore;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class DBHandler extends SQLiteOpenHelper {

    public static final int DATABASE_VERSION = 1;
    public static final String DATABASE_NAME = "charts";
    private SQLiteDatabase db;

    public  DBHandler(Context context){
        super(context, DATABASE_NAME, null, DATABASE_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db){
        String[] queries = {
                "CREATE TABLE airports(id INTEGER PRIMARY KEY AUTOINCREMENT, icao VARCHAR(4));",
                "CREATE TABLE charts(id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT, chart BLOB, " +
                        "cords1x DOUBLE, cords1y DOUBLE, " +
                        "cords2x DOUBLE, cords2y DOUBLE, " +
                        "pixel1x INT, pixel1y INT, " +
                        "pixel2x INT, pixel2y INT, " +
                        "icao VARCHAR(4))"
        };

        for (String query:queries) {
            db.execSQL(query);
        }
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion){

    }

    public long addAirport(String icao){

        SQLiteDatabase db = getWritableDatabase();

        ContentValues contentValues = new ContentValues();
        contentValues.put("icao", icao);
        long id = db.insert("airports", null, contentValues);
        return id;

    }

    public boolean getAirportExists(String icao){

        SQLiteDatabase db = getWritableDatabase();

        String query = "SELECT COUNT(*) FROM airports WHERE icao=?";
        Cursor cursor = db.rawQuery(query, new String[]{icao});

        cursor.moveToFirst();

        if(cursor.getInt(0)>0) return true;
        else return false;

    }

    public List<String> getAirportsList(){

        List<String> AirportsList = new ArrayList<String>();

        SQLiteDatabase db = getReadableDatabase();

        String query = "SELECT icao FROM airports";
        Cursor cursor = db.rawQuery(query, null);
        cursor.moveToFirst();
        int icao = cursor.getColumnIndex("icao");
        Log.d("Airport count", String.valueOf(cursor.getCount()));
        if(cursor.moveToFirst()){

            while(!cursor.isAfterLast()){
                AirportsList.add(cursor.getString(icao));
                cursor.moveToNext();
            }

        }

        return AirportsList;

    }

    public boolean addChart(String icao, Uri uri, PointF geoCoords1, PointF geoCoords2,
                            PointF pixelCoords1, PointF pixelCoords2, Context context){
        //TODO: Convert GeoCoords and PixelCoords to PointF[]

        SQLiteDatabase db = getWritableDatabase();

        //Code for converting image to bitmap
        Bitmap chartBitmap;
        try{
            chartBitmap = MediaStore.Images.Media.getBitmap(context.getContentResolver(), uri);
        }catch (Exception e){
            return false;
        }

        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        chartBitmap.compress(Bitmap.CompressFormat.JPEG, 100, stream);
        byte[] byteArray = stream.toByteArray();
        chartBitmap.recycle();

        ContentValues chartValues = new ContentValues();
        chartValues.put("icao", icao);
        chartValues.put("cords1x", Double.valueOf(geoCoords1.x));
        chartValues.put("cords1y", Double.valueOf(geoCoords1.y));
        chartValues.put("cords2x", Double.valueOf(geoCoords2.x));
        chartValues.put("cords2y", Double.valueOf(geoCoords2.y));
        chartValues.put("pixel1x", Math.round(pixelCoords1.x));
        chartValues.put("pixel1y", Math.round(pixelCoords1.y));
        chartValues.put("pixel2x", Math.round(pixelCoords2.x));
        chartValues.put("pixel2y", Math.round(pixelCoords2.y));
        chartValues.put("chart", byteArray);
        chartValues.put("name", "check");

        try{
            db.insert("charts", null, chartValues);
            return true;
        }catch (Exception e){
            Log.e("DBInsertException", e.getMessage());
            return false;
        }
    }

    public List<Chart> getChartsList(String icao){

        List<Chart> chartsList = new ArrayList<>();

        SQLiteDatabase db = getReadableDatabase();

        String query = "SELECT id, name FROM charts WHERE icao=?";
        Cursor cursor = db.rawQuery(query, new String[]{icao});

        int idColumn = cursor.getColumnIndex("id");
        int nameColumn = cursor.getColumnIndex("name");

        Chart tempChart = new Chart();

        if (cursor.moveToFirst()){
            while(!cursor.isAfterLast()){

                tempChart.id = cursor.getInt(idColumn);
                tempChart.name = cursor.getString(nameColumn);
                chartsList.add(tempChart);

                cursor.moveToNext();
            }
        }

        return chartsList;

    }
}
